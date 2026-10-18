/* Tests Game Boy cartridge ROM/RAM bank mirroring in mupen64plus-core's
 * gb_cart.c (gb_ram_mirroring.diff) and the MBC3 RTC's start time
 * (gb_rtc_start_time.diff). Build and run against a core checkout:
 *   gcc -std=gnu99 -fsanitize=address,undefined -I CORE/src -o gb_cart_test \
 *     gb_cart_test.c CORE/src/device/gb/{gb_cart,mbc3_rtc,m64282fp}.c
 * Prints PASS/FAIL per check; upstream fails 10 mirroring checks and 5 RTC
 * checks. */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "api/m64p_types.h"
#include "backends/api/clock_backend.h"
#include "backends/api/storage_backend.h"
#include "device/gb/gb_cart.h"

/* stubs for the core functions gb_cart.c uses */
static int warnings;
void DebugMessage(int level, const char* message, ...)
{
    va_list args;
    if (level > M64MSG_WARNING) return;
    va_start(args, message);
    printf("    core: ");
    vprintf(message, args);
    printf("\n");
    va_end(args);
    ++warnings;
}
void cv_imshow(const char* name, unsigned int width, unsigned int height, int channels, void* data) {}

struct buf { uint8_t* data; size_t size; };
static uint8_t* buf_data(const void* s) { return ((const struct buf*)s)->data; }
static size_t buf_size(const void* s) { return ((const struct buf*)s)->size; }
static void buf_save(void* s, size_t start, size_t size) {}
static const struct storage_backend_interface ibuf = { buf_data, buf_size, buf_save };

static struct buf rom, ram;
static void init_rom(void* u, void** s, const struct storage_backend_interface** i) { *s = &rom; *i = &ibuf; }
static void init_ram(void* u, size_t size, void** s, const struct storage_backend_interface** i)
{
    ram.size = size;
    ram.data = calloc(size, 1);
    *s = &ram; *i = &ibuf;
}
static void release(void* u) {}

/* the host clock: stopped unless a test moves it, so the RTC registers keep
 * what was written */
static time_t fake_now;
static time_t get_time(void* clock) { return fake_now; }
static const struct clock_backend_interface iclock = { get_time };

static int failures;

static void make_cart(struct gb_cart* cart, uint8_t type, size_t rom_size, uint8_t ram_code)
{
    size_t i;
    free(rom.data);
    free(ram.data);
    ram.data = NULL;
    ram.size = 0;
    rom.size = rom_size;
    rom.data = malloc(rom_size);
    /* each 16 KB ROM bank is filled with its bank number */
    for (i = 0; i < rom_size; ++i) rom.data[i] = (uint8_t)(i / 0x4000);
    rom.data[0x147] = type;
    rom.data[0x149] = ram_code;
    memset(cart, 0, sizeof(*cart));
    init_gb_cart(cart, NULL, init_rom, release, NULL, init_ram, release,
                 NULL, &iclock, NULL, NULL, NULL, NULL);
    poweron_gb_cart(cart);
}

static void wr(struct gb_cart* cart, uint16_t address, uint8_t value)
{
    write_gb_cart(cart, address, &value, 1);
}

/* reads a 32-byte block (the Transfer Pak's size) into a buffer prefilled
 * with 0xee, so a read that returns nothing shows up as 0xee */
static void rd(struct gb_cart* cart, uint16_t address, uint8_t* out)
{
    memset(out, 0xee, 32);
    read_gb_cart(cart, address, out, 32);
}

static void expect(const char* what, const uint8_t* got, uint8_t want)
{
    int ok = 1, i;
    for (i = 0; i < 32; ++i) ok &= (got[i] == want);
    printf("  %s %s (got %02x, want %02x)\n", ok ? "PASS" : "FAIL", what, got[0], want);
    if (!ok) ++failures;
}

static void fill(struct gb_cart* cart, uint16_t address, uint8_t value)
{
    uint8_t block[32];
    memset(block, value, 32);
    write_gb_cart(cart, address, block, 32);
}

int main(void)
{
    struct gb_cart cart;
    uint8_t got[32];
    int bank;

    printf("MBC3+RAM+BATT (Red), 32 KB RAM: banks 4-7 mirror banks 0-3\n");
    make_cart(&cart, 0x13, 0x100000, 0x03);
    wr(&cart, 0x0000, 0x0a);
    for (bank = 0; bank < 4; ++bank) {
        wr(&cart, 0x4000, bank);
        fill(&cart, 0xa000, 0x10 + bank);
    }
    for (bank = 0; bank < 8; ++bank) {
        char what[64];
        wr(&cart, 0x4000, bank);
        rd(&cart, 0xa000, got);
        snprintf(what, sizeof(what), "read bank %d $A000", bank);
        expect(what, got, 0x10 + (bank & 3));
    }
    wr(&cart, 0x4000, 5);
    fill(&cart, 0xbfe0, 0x77);
    wr(&cart, 0x4000, 1);
    rd(&cart, 0xbfe0, got);
    expect("write bank 5 $BFE0, read bank 1", got, 0x77);
    wr(&cart, 0x4000, 0);
    rd(&cart, 0xbfe0, got);
    expect("bank 0 $BFE0 unchanged", got, 0x00);

    printf("MBC3+TIMER+RAM+BATT (Crystal), 2 MB ROM: bank 4 mirrors bank 0, RTC registers unaffected\n");
    make_cart(&cart, 0x10, 0x200000, 0x03);
    wr(&cart, 0x0000, 0x0a);
    wr(&cart, 0x4000, 0);
    fill(&cart, 0xa000, 0x5a);
    wr(&cart, 0x4000, 4);
    rd(&cart, 0xa000, got);
    expect("read bank 4 $A000", got, 0x5a);
    wr(&cart, 0x2000, 0x7f);
    rd(&cart, 0x4000, got);
    expect("ROM bank $7f", got, 0x7f);
    /* the RTC day counter's high bits: write the halt flag, read it back */
    wr(&cart, 0x4000, 0x0c);
    wr(&cart, 0xa000, 0x40);
    wr(&cart, 0x6000, 0x00);
    wr(&cart, 0x6000, 0x01);
    rd(&cart, 0xa000, got);
    expect("RTC register $0c halt flag", got, 0x40);

    printf("MBC3+TIMER+RAM+BATT, powered on in 2027: RTC counts from 0\n");
    fake_now = 1800000000;
    make_cart(&cart, 0x10, 0x200000, 0x03);
    wr(&cart, 0x0000, 0x0a);
    wr(&cart, 0x6000, 0x00);
    wr(&cart, 0x6000, 0x01);
    wr(&cart, 0x4000, 0x0c);
    rd(&cart, 0xa000, got);
    expect("RTC days high (carry, halt, day bit 8)", got, 0x00);
    wr(&cart, 0x4000, 0x0b);
    rd(&cart, 0xa000, got);
    expect("RTC days low", got, 0x00);
    /* 2 days, 3 hours, 4 minutes and 5 seconds later */
    fake_now += ((2 * 24 + 3) * 60 + 4) * 60 + 5;
    wr(&cart, 0x6000, 0x00);
    wr(&cart, 0x6000, 0x01);
    {
        static const uint8_t want[] = { 5, 4, 3, 2, 0 };
        static const char* const names[] = { "seconds", "minutes", "hours", "days low", "days high" };
        for (bank = 0; bank < 5; ++bank) {
            char what[64];
            wr(&cart, 0x4000, 0x08 + bank);
            rd(&cart, 0xa000, got);
            snprintf(what, sizeof(what), "RTC %s after 2d 3h 4m 5s", names[bank]);
            expect(what, got, want[bank]);
        }
    }
    fake_now = 0;

    printf("MBC5+RAM+BATT, 8 KB RAM: banks 1-7 mirror bank 0\n");
    make_cart(&cart, 0x1b, 0x20000, 0x02);
    wr(&cart, 0x0000, 0x0a);
    wr(&cart, 0x4000, 0);
    fill(&cart, 0xa000, 0x42);
    wr(&cart, 0x4000, 3);
    rd(&cart, 0xa000, got);
    expect("read bank 3 $A000", got, 0x42);

    printf("MBC5, 128 KB ROM (8 banks): bank 9 mirrors bank 1\n");
    wr(&cart, 0x2000, 9);
    rd(&cart, 0x4000, got);
    expect("ROM bank 9", got, 0x01);
    wr(&cart, 0x2000, 7);
    rd(&cart, 0x4000, got);
    expect("ROM bank 7", got, 0x07);

    printf("MBC2, 512x4 bit RAM: $A200 mirrors $A000\n");
    make_cart(&cart, 0x06, 0x40000, 0x00);
    wr(&cart, 0x0000, 0x0a);
    fill(&cart, 0xa000, 0x03);
    rd(&cart, 0xa200, got);
    expect("read $A200", got, 0x03);

    printf("ROM only + RAM, 2 KB RAM: $A800 mirrors $A000\n");
    make_cart(&cart, 0x08, 0x8000, 0x01);
    fill(&cart, 0xa000, 0x24);
    rd(&cart, 0xa800, got);
    expect("read $A800", got, 0x24);

    printf("%d warnings, %s\n", warnings, failures ? "FAILED" : "ALL PASS");
    return failures != 0;
}
