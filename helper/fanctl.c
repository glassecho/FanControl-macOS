// fanctl — privileged helper for the FanControl GUI.
//
//   fanctl read                          JSON state (no root needed)
//   fanctl duty <ch> <0-100>             manual duty, %          (root)
//   fanctl rpm  <ch> <rpm>               manual target RPM       (root)
//   fanctl bios <ch>                     return one fan to BIOS  (root)
//   fanctl bios-all                      return all fans to BIOS (root)
//   fanctl conf <file>                   install gpufand config  (root)
//   fanctl daemon <start|stop|restart>                           (root)
//   fanctl version
//
// Build: cc -O2 -o fanctl fanctl.c -framework IOKit

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

#define HELPER_VERSION "1.2"
#define GPUFAND_CONF   "/usr/local/etc/gpufand.conf"
#define GPUFAND_PLIST  "/Library/LaunchDaemons/com.shohart.gpufand.plist"
#define GPUFAND_SVC    "system/com.shohart.gpufand"
#define GPUFAND_STATUS "/var/run/gpufand.json"
#define FANCONTROL_CONF "/usr/local/etc/fancontrol.conf"

#define MAX_FANS 8
#define DEFAULT_PUMP_CH 6   /* AIO pump channel — overridable in fancontrol.conf */

/* 水泵通道。每台机器的风扇通道布局不同，所以从 fancontrol.conf 读，
 * 读不到就用 6（本机 ASUS + NCT679BD 的布局）。UI 会把它锁死不让调速。 */
static int g_pump_ch = DEFAULT_PUMP_CH;
static int g_pump_from_conf = 0;   /* 0 = 用的是默认值，换机器时应当确认 */

static char *str_trim(char *s) {
    while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n') s++;
    char *e = s + strlen(s);
    while (e > s && (e[-1] == ' ' || e[-1] == '\t' || e[-1] == '\r' || e[-1] == '\n')) *--e = 0;
    return s;
}

/* 解析 /usr/local/etc/fancontrol.conf（简单的 key = value，# 起注释）
 * 可用环境变量 FANCONTROL_CONF_FILE 覆盖路径（便于测试/多机部署） */
static void load_fancontrol_conf(void) {
    const char *path = getenv("FANCONTROL_CONF_FILE");
    if (!path || !*path) path = FANCONTROL_CONF;
    FILE *f = fopen(path, "r");
    if (!f) return;
    char line[256];
    while (fgets(line, sizeof line, f)) {
        char *hash = strchr(line, '#');
        if (hash) *hash = 0;
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = 0;
        char *k = str_trim(line), *v = str_trim(eq + 1);
        if (!strcmp(k, "pump_channel")) {
            int n = atoi(v);
            if (n >= 0 && n < MAX_FANS) { g_pump_ch = n; g_pump_from_conf = 1; }
        }
    }
    fclose(f);
}

/* ---------------------------------------------------------------- SMC glue */

enum { kSMCHandleYPCEvent = 2 };
enum { kSMCReadKey = 5, kSMCWriteKey = 6, kSMCGetKeyFromIndex = 8, kSMCGetKeyInfo = 9 };

typedef unsigned char SMCBytes_t[32];
typedef struct { char major, minor, build, reserved[1]; uint16_t release; } SMCVers_t;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimit_t;
typedef struct { uint32_t dataSize; uint32_t dataType; uint8_t dataAttributes; } SMCKeyInfo_t;
typedef struct {
    uint32_t key;
    SMCVers_t vers;
    SMCPLimit_t pLimitData;
    SMCKeyInfo_t keyInfo;
    char result;
    char status;
    uint8_t data8;
    uint32_t data32;
    SMCBytes_t bytes;
} SMCParamStruct;

static io_connect_t g_conn = IO_OBJECT_NULL;
static kern_return_t g_lastKr = KERN_SUCCESS;

static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}
static void unfourcc(uint32_t k, char out[5]) {
    out[0] = (k >> 24) & 0xff; out[1] = (k >> 16) & 0xff;
    out[2] = (k >> 8) & 0xff;  out[3] = k & 0xff; out[4] = 0;
    for (int i = 0; i < 4; i++) if (out[i] < 32 || out[i] > 126) out[i] = '?';
}

static int openSMC(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &g_conn);
    IOObjectRelease(svc);
    return kr == KERN_SUCCESS ? 0 : -1;
}

static SMCParamStruct smcCall(SMCParamStruct *in) {
    SMCParamStruct out; memset(&out, 0, sizeof(out));
    size_t is = sizeof(SMCParamStruct), os = sizeof(SMCParamStruct);
    g_lastKr = IOConnectCallStructMethod(g_conn, kSMCHandleYPCEvent, in, is, &out, &os);
    return out;
}

static SMCParamStruct getInfo(uint32_t key) {
    SMCParamStruct in; memset(&in, 0, sizeof(in));
    in.key = key; in.data8 = kSMCGetKeyInfo;
    return smcCall(&in);
}

static int readBytes(uint32_t key, uint8_t *bytes, uint32_t *size, uint32_t *typeOut) {
    SMCParamStruct info = getInfo(key);
    if (info.result) return -(int)info.result;
    uint32_t sz = info.keyInfo.dataSize;
    if (sz == 0 || sz > 32) return -100;
    SMCParamStruct in; memset(&in, 0, sizeof(in));
    in.key = key; in.data8 = kSMCReadKey; in.keyInfo.dataSize = sz;
    SMCParamStruct out = smcCall(&in);
    if (g_lastKr != KERN_SUCCESS) return -1000;
    if (out.result) return -(int)out.result;
    memcpy(bytes, out.bytes, sz);
    if (size) *size = sz;
    if (typeOut) *typeOut = info.keyInfo.dataType;
    return 0;
}

static int writeBytes(uint32_t key, uint32_t type, const uint8_t *bytes, uint32_t size) {
    SMCParamStruct in; memset(&in, 0, sizeof(in));
    in.key = key;
    in.keyInfo.dataSize = size;
    in.keyInfo.dataType = type;
    in.data8 = kSMCWriteKey;
    memcpy(in.bytes, bytes, size);
    SMCParamStruct out = smcCall(&in);
    if (g_lastKr != KERN_SUCCESS) return -1000;
    return out.result ? -(int)out.result : 0;
}

static double decodeVal(uint32_t t, const uint8_t *b, uint32_t s) {
    if (t == fourcc("sp78") && s >= 2) return (double)(int16_t)((b[0] << 8) | b[1]) / 256.0;
    if (t == fourcc("fpe2") && s >= 2) return (double)(int16_t)((b[0] << 8) | b[1]) / 4.0;
    if (t == fourcc("flt ") && s >= 4) { float f; uint8_t x[4] = {b[3], b[2], b[1], b[0]}; memcpy(&f, x, 4); return (double)f; }
    if (t == fourcc("ui8 ") && s >= 1) return (double)b[0];
    if (t == fourcc("ui16") && s >= 2) return (double)((b[0] << 8) | b[1]);
    if (t == fourcc("ui32") && s >= 4) return (double)(((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3]);
    if (t == fourcc("si8 ") && s >= 1) return (double)(int8_t)b[0];
    if (t == fourcc("si16") && s >= 2) return (double)(int16_t)((b[0] << 8) | b[1]);
    return NAN;
}

static int encodeVal(uint32_t t, double v, uint8_t *out) {
    if (t == fourcc("sp78")) { int16_t r = (int16_t)lround(v * 256.0); out[0] = (r >> 8) & 0xff; out[1] = r & 0xff; return 2; }
    if (t == fourcc("fpe2")) { int16_t r = (int16_t)lround(v * 4.0);   out[0] = (r >> 8) & 0xff; out[1] = r & 0xff; return 2; }
    if (t == fourcc("ui8 ")) { out[0] = (uint8_t)lround(v); return 1; }
    if (t == fourcc("ui16")) { uint16_t r = (uint16_t)lround(v); out[0] = (r >> 8) & 0xff; out[1] = r & 0xff; return 2; }
    if (t == fourcc("ui32")) { uint32_t u = (uint32_t)lround(v); out[0] = (u >> 24) & 0xff; out[1] = (u >> 16) & 0xff; out[2] = (u >> 8) & 0xff; out[3] = u & 0xff; return 4; }
    if (t == fourcc("si8 ")) { out[0] = (uint8_t)(int8_t)lround(v); return 1; }
    if (t == fourcc("si16")) { int16_t r = (int16_t)lround(v); out[0] = (r >> 8) & 0xff; out[1] = r & 0xff; return 2; }
    return -1;
}

/* returns 0 on success; fills *val when readable */
static int smcReadNum(const char *key4, double *val) {
    uint8_t b[32]; uint32_t sz = 0, ty = 0;
    if (readBytes(fourcc(key4), b, &sz, &ty)) return -1;
    double v = decodeVal(ty, b, sz);
    if (isnan(v)) return -1;
    if (val) *val = v;
    return 0;
}

static int smcWriteNum(const char *key4, double val) {
    SMCParamStruct info = getInfo(fourcc(key4));
    if (info.result) return -1;
    uint8_t b[32];
    int n = encodeVal(info.keyInfo.dataType, val, b);
    if (n < 0 || (uint32_t)n != info.keyInfo.dataSize) return -2;
    return writeBytes(fourcc(key4), info.keyInfo.dataType, b, (uint32_t)n);
}

static int smcHasKey(const char *key4) {
    return getInfo(fourcc(key4)).result == 0;
}

static void fankey(char out[5], int ch, const char *suffix) {
    snprintf(out, 5, "F%d%s", ch, suffix);
}

/* ------------------------------------------------------ GPU（只读，不控速） */
/* 显卡风扇由显卡固件的 PowerPlay 表 + AMD 驱动共同管理，macOS 没有对外
 * 开放的写入接口，所以这里只做监控：从 IORegistry 的 IOAccelerator 节点
 * 读 PerformanceStatistics，取风扇转速/占空比/温度/功耗/频率/占用率。
 * 普通用户即可读取，不需要 root。 */

typedef struct {
    int valid;
    int has_fan_rpm, has_fan_pct, has_temp, has_power, has_core, has_mem, has_util;
    double fan_rpm, fan_pct, temp, power, core, mem, util;
} gpu_info_t;

static int cf_num(CFDictionaryRef d, const char *key, double *out) {
    CFStringRef k = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
    if (!k) return 0;
    int ok = 0;
    CFTypeRef v = CFDictionaryGetValue(d, k);
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) {
        double x = 0;
        if (CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &x)) { *out = x; ok = 1; }
    }
    CFRelease(k);
    return ok;
}

static void read_gpu(gpu_info_t *g) {
    memset(g, 0, sizeof *g);
    CFMutableDictionaryRef match = IOServiceMatching("IOAccelerator");
    if (!match) return;
    io_iterator_t it = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) != KERN_SUCCESS) return;

    io_service_t svc;
    while ((svc = IOIteratorNext(it))) {
        CFTypeRef ps = IORegistryEntryCreateCFProperty(svc, CFSTR("PerformanceStatistics"),
                                                      kCFAllocatorDefault, 0);
        if (ps && CFGetTypeID(ps) == CFDictionaryGetTypeID()) {
            CFDictionaryRef d = (CFDictionaryRef)ps;
            gpu_info_t t; memset(&t, 0, sizeof t);
            t.has_fan_rpm = cf_num(d, "Fan Speed(RPM)",       &t.fan_rpm);
            t.has_fan_pct = cf_num(d, "Fan Speed(%)",         &t.fan_pct);
            t.has_temp    = cf_num(d, "Temperature(C)",       &t.temp);
            t.has_power   = cf_num(d, "Total Power(W)",       &t.power);
            t.has_core    = cf_num(d, "Core Clock(MHz)",      &t.core);
            t.has_mem     = cf_num(d, "Memory Clock(MHz)",    &t.mem);
            t.has_util    = cf_num(d, "Device Utilization %", &t.util);
            /* 同一块卡可能有两个加速器实例（GFX / 计算），取第一个带风扇数据的 */
            if (!g->valid && (t.has_fan_rpm || t.has_fan_pct)) { t.valid = 1; *g = t; }
        }
        if (ps) CFRelease(ps);
        IOObjectRelease(svc);
    }
    IOObjectRelease(it);
}

/* 只输出实际读到的字段，界面按可选值解析 */
static void emit_gpu(const gpu_info_t *g) {
    if (!g->valid) return;
    printf(",\"gpu\":{");
    int f = 1;
    #define GE(key, flag, fmt, val) do { \
        if (flag) { printf("%s\"%s\":" fmt, f ? "" : ",", key, val); f = 0; } \
    } while (0)
    GE("fanRPM",      g->has_fan_rpm, "%.0f", g->fan_rpm);
    GE("fanPercent",  g->has_fan_pct, "%.1f", g->fan_pct);
    GE("temp",        g->has_temp,    "%.0f", g->temp);
    GE("power",       g->has_power,   "%.1f", g->power);
    GE("coreClock",   g->has_core,    "%.0f", g->core);
    GE("memClock",    g->has_mem,     "%.0f", g->mem);
    GE("utilization", g->has_util,    "%.0f", g->util);
    #undef GE
    printf("}");
}

/* ---------------------------------------------------------------- helpers */

static const char *need_root(const char *what) {
    if (geteuid() != 0) {
        static char msg[160];
        snprintf(msg, sizeof msg, "%s needs root", what);
        return msg;
    }
    return NULL;
}

/* JSON 字符串转义。>= 0x80 的字节按 UTF-8 原样透传（进程名可能是中文），
 * 只把控制字符挡掉，避免产出非法 JSON。 */
static void jesc(const char *s) {
    for (; *s; s++) {
        unsigned char c = (unsigned char)*s;
        if (c == '"' || c == '\\') putchar('\\'), putchar(c);
        else if (c == '\n') fputs("\\n", stdout);
        else if (c == '\r') fputs("\\r", stdout);
        else if (c == '\t') fputs("\\t", stdout);
        else if (c >= 32) putchar(c);
        else putchar('?');
    }
}

static void fan_name(int ch, char *out, size_t n) {
    char key[5]; fankey(key, ch, "ID");
    uint8_t b[32]; uint32_t sz = 0, ty = 0;
    out[0] = 0;
    if (readBytes(fourcc(key), b, &sz, &ty)) return;
    /* 16 bytes: 4 header bytes then the name */
    size_t start = sz >= 16 ? 4 : 0, k = 0;
    for (size_t i = start; i < sz && k + 1 < n; i++) {
        if (b[i] >= 32 && b[i] < 127) out[k++] = (char)b[i];
    }
    out[k] = 0;
    if (!out[0]) snprintf(out, n, "F%d", ch);
}

/* ---------------------------------------------------------------- commands */

static int cmd_read(void) {
    if (openSMC()) { fprintf(stderr, "cannot open AppleSMC\n"); return 1; }

    printf("{\"ok\":true,\"pumpChannel\":%d,\"pumpConfigured\":%s,\"fans\":[",
           g_pump_ch, g_pump_from_conf ? "true" : "false");
    double fnum = 0;
    int nfans = smcReadNum("FNum", &fnum) == 0 ? (int)fnum : MAX_FANS;
    if (nfans < 0 || nfans > MAX_FANS) nfans = MAX_FANS;
    int first = 1;
    for (int ch = 0; ch < nfans; ch++) {
        char kAc[5]; fankey(kAc, ch, "Ac");
        if (!smcHasKey(kAc)) continue;
        char kPw[5], kMd[5], kTg[5], kMn[5], kMx[5];
        fankey(kPw, ch, "Pw"); fankey(kMd, ch, "Md"); fankey(kTg, ch, "Tg");
        fankey(kMn, ch, "Mn"); fankey(kMx, ch, "Mx");
        double rpm = -1, pwm = -1, md = -1, tg = -1, mn = -1, mx = -1;
        smcReadNum(kAc, &rpm); smcReadNum(kPw, &pwm); smcReadNum(kMd, &md);
        smcReadNum(kTg, &tg);  smcReadNum(kMn, &mn);  smcReadNum(kMx, &mx);
        char name[24]; fan_name(ch, name, sizeof name);
        int controllable = smcHasKey(kMd) && smcHasKey(kTg);
        printf("%s{\"ch\":%d,\"name\":\"", first ? "" : ",", ch); jesc(name);
        printf("\",\"rpm\":%.0f,\"pwm\":%.0f,\"duty\":%.1f,\"mode\":%.0f,\"target\":%.1f,"
               "\"min\":%.0f,\"max\":%.0f,\"controllable\":%s}",
               rpm < 0 ? 0 : rpm, pwm < 0 ? 0 : pwm, pwm < 0 ? 0 : pwm * 100.0 / 255.0,
               md < 0 ? 0 : md, tg < 0 ? 0 : tg, mn < 0 ? 0 : mn, mx < 0 ? 0 : mx,
               controllable ? "true" : "false");
        first = 0;
    }
    printf("],\"sensors\":[");

    /* enumerate every T* key of type sp78 */
    uint8_t b[32]; uint32_t sz = 0, ty = 0;
    int firsts = 1;
    if (readBytes(fourcc("#KEY"), b, &sz, &ty) == 0 && sz >= 4) {
        uint32_t count = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3];
        if (count > 4000) count = 4000;
        for (uint32_t i = 0; i < count; i++) {
            SMCParamStruct in; memset(&in, 0, sizeof(in));
            in.data8 = kSMCGetKeyFromIndex; in.data32 = i;
            SMCParamStruct out = smcCall(&in);
            if (g_lastKr != KERN_SUCCESS || out.result) continue;
            char nm[5]; unfourcc(out.key, nm);
            if (nm[0] != 'T') continue;
            SMCParamStruct info = getInfo(out.key);
            if (info.result) continue;
            uint32_t t = info.keyInfo.dataType;
            if (t != fourcc("sp78") && t != fourcc("flt ")) continue;
            double v = 0;
            if (smcReadNum(nm, &v)) continue;
            if (v < -20 || v > 150) continue;
            printf("%s{\"key\":\"", firsts ? "" : ","); jesc(nm);
            printf("\",\"value\":%.2f}", v);
            firsts = 0;
        }
    }
    printf("]");

    /* 显卡（只读监控；无驱动的卡不会出现，比如 macOS 下的 NVIDIA 30 系） */
    gpu_info_t gpu; read_gpu(&gpu);
    emit_gpu(&gpu);

    printf(",\"service\":{");

    struct stat st;
    int installed = stat(GPUFAND_PLIST, &st) == 0;
    int confexists = stat(GPUFAND_CONF, &st) == 0;
    int running = 0;
    if (stat(GPUFAND_STATUS, &st) == 0 && time(NULL) - st.st_mtime <= 12) running = 1;
    printf("\"installed\":%s,\"running\":%s,\"conf\":%s}",
           installed ? "true" : "false", running ? "true" : "false", confexists ? "true" : "false");

    printf(",\"root\":%s}\n", geteuid() == 0 ? "true" : "false");
    return 0;
}

static int parse_ch(const char *s, int *ch) {
    char *end = NULL;
    long v = strtol(s, &end, 10);
    if (!end || *end || v < 0 || v >= MAX_FANS) return -1;
    *ch = (int)v;
    return 0;
}

static int cmd_set(const char *mode, int ch, double value) {
    char kTg[5], kMd[5];
    fankey(kTg, ch, "Tg"); fankey(kMd, ch, "Md");
    if (!smcHasKey(kTg) || !smcHasKey(kMd)) {
        fprintf(stderr, "fan %d is not controllable\n", ch);
        return 3;
    }
    int rc = smcWriteNum(kTg, value);
    if (rc) { fprintf(stderr, "write F%dTg failed (%d)\n", ch, rc); return 1; }
    rc = smcWriteNum(kMd, !strcmp(mode, "duty") ? 2 : 1);
    if (rc) { fprintf(stderr, "write F%dMd failed (%d)\n", ch, rc); return 1; }
    printf("fan %d: %s %.0f\n", ch, mode, value);
    return 0;
}

static int cmd_bios(int ch) {
    char kMd[5]; fankey(kMd, ch, "Md");
    if (!smcHasKey(kMd)) return 0;
    int rc = smcWriteNum(kMd, 0);
    if (rc) { fprintf(stderr, "write F%dMd failed (%d)\n", ch, rc); return 1; }
    printf("fan %d -> BIOS\n", ch);
    return 0;
}

static int run(const char *cmd, const char *a1, const char *a2, const char *a3, const char *a4) {
    pid_t p = fork();
    if (p < 0) return -1;
    if (p == 0) {
        if (a4) execl(cmd, cmd, a1, a2, a3, a4, (char *)NULL);
        else if (a3) execl(cmd, cmd, a1, a2, a3, (char *)NULL);
        else if (a2) execl(cmd, cmd, a1, a2, (char *)NULL);
        else if (a1) execl(cmd, cmd, a1, (char *)NULL);
        else execl(cmd, cmd, (char *)NULL);
        _exit(127);
    }
    int st = 0;
    if (waitpid(p, &st, 0) < 0) return -1;
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

static int cmd_daemon(const char *action) {
    if (!strcmp(action, "stop")) {
        run("/bin/launchctl", "bootout", GPUFAND_SVC, NULL, NULL);
        printf("service stopped\n");
        return 0;
    }
    if (!strcmp(action, "start")) {
        if (run("/bin/launchctl", "bootstrap", "system", GPUFAND_PLIST, NULL)) {
            fprintf(stderr, "bootstrap failed\n");
            return 1;
        }
        printf("service started\n");
        return 0;
    }
    if (!strcmp(action, "restart")) {
        run("/bin/launchctl", "bootout", GPUFAND_SVC, NULL, NULL);
        usleep(600000);
        if (run("/bin/launchctl", "bootstrap", "system", GPUFAND_PLIST, NULL)) {
            fprintf(stderr, "bootstrap failed\n");
            return 1;
        }
        printf("service restarted\n");
        return 0;
    }
    if (!strcmp(action, "reload")) {
        if (run("/bin/launchctl", "kill", "HUP", GPUFAND_SVC, NULL)) {
            fprintf(stderr, "reload failed\n");
            return 1;
        }
        printf("service reloaded\n");
        return 0;
    }
    fprintf(stderr, "unknown daemon action '%s'\n", action);
    return 2;
}

static int cmd_conf(const char *src) {
    FILE *in = fopen(src, "r");
    if (!in) { fprintf(stderr, "cannot read %s\n", src); return 1; }
    char buf[8192];
    size_t n = fread(buf, 1, sizeof(buf) - 1, in);
    fclose(in);
    buf[n] = 0;
    /* minimal sanity check: must contain at least one "fans =" line */
    if (!strstr(buf, "fans")) { fprintf(stderr, "config has no 'fans' line\n"); return 2; }

    char tmp[] = GPUFAND_CONF ".tmp";
    FILE *out = fopen(tmp, "w");
    if (!out) { fprintf(stderr, "cannot write %s\n", tmp); return 1; }
    fwrite(buf, 1, n, out);
    fclose(out);
    chmod(tmp, 0644);
    if (rename(tmp, GPUFAND_CONF)) { fprintf(stderr, "rename failed: %s\n", strerror(errno)); return 1; }
    printf("config installed\n");
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr,
                "usage: %s read\n"
                "       %s gpu\n"
                "       %s duty <ch> <0-100>   (root)\n"
                "       %s rpm  <ch> <rpm>     (root)\n"
                "       %s bios <ch>|all       (root)\n"
                "       %s conf <file>         (root)\n"
                "       %s daemon start|stop|restart|reload  (root)\n",
                argv[0], argv[0], argv[0], argv[0], argv[0], argv[0], argv[0]);
        return 2;
    }
    const char *cmd = argv[1];

    load_fancontrol_conf();   /* 水泵通道等本机参数 */

    if (!strcmp(cmd, "version")) { printf("%s\n", HELPER_VERSION); return 0; }
    if (!strcmp(cmd, "read")) return cmd_read();

    /* 显卡监控单独一条命令，方便在终端里调试（只读，不需要 root） */
    if (!strcmp(cmd, "gpu")) {
        gpu_info_t g; read_gpu(&g);
        printf("{\"ok\":true");
        emit_gpu(&g);
        printf("}\n");
        return 0;
    }

    const char *err;

    if (!strcmp(cmd, "duty") || !strcmp(cmd, "rpm")) {
        if ((err = need_root(cmd))) { fprintf(stderr, "%s\n", err); return 4; }
        int ch;
        if (argc < 4 || parse_ch(argv[2], &ch)) { fprintf(stderr, "bad channel\n"); return 2; }
        double v = strtod(argv[3], NULL);
        if (!strcmp(cmd, "duty")) v = fmax(0.0, fmin(100.0, v));
        else v = fmax(0.0, fmin(10000.0, v));
        if (openSMC()) { fprintf(stderr, "cannot open AppleSMC\n"); return 1; }
        return cmd_set(cmd, ch, v);
    }

    if (!strcmp(cmd, "bios")) {
        if ((err = need_root(cmd))) { fprintf(stderr, "%s\n", err); return 4; }
        if (openSMC()) { fprintf(stderr, "cannot open AppleSMC\n"); return 1; }
        if (argc >= 3 && !strcmp(argv[2], "all")) {
            for (int ch = 0; ch < MAX_FANS; ch++) cmd_bios(ch);
            return 0;
        }
        int ch;
        if (argc < 3 || parse_ch(argv[2], &ch)) { fprintf(stderr, "bad channel\n"); return 2; }
        return cmd_bios(ch);
    }

    if (!strcmp(cmd, "conf")) {
        if ((err = need_root(cmd))) { fprintf(stderr, "%s\n", err); return 4; }
        if (argc < 3) { fprintf(stderr, "conf needs a file\n"); return 2; }
        return cmd_conf(argv[2]);
    }

    if (!strcmp(cmd, "daemon")) {
        if ((err = need_root(cmd))) { fprintf(stderr, "%s\n", err); return 4; }
        if (argc < 3) { fprintf(stderr, "daemon needs an action\n"); return 2; }
        return cmd_daemon(argv[2]);
    }

    fprintf(stderr, "unknown command '%s'\n", cmd);
    return 2;
}
