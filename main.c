#include "xil_printf.h"
#include "xil_io.h"
#include "sleep.h"
#include "xparameters.h"

// ── 주소 확인 후 수정 ──────────────────────────────
// Vivado Address Editor에서 확인한 주소로 변경
#define TRNG_BASE     0x40000000

// 레지스터 오프셋
#define REG_CTRL      0x00  // [0]=enable [1]=sw_reset
#define REG_STATUS    0x04  // [0]=data_valid [1]=fifo_empty
                            // [2]=fifo_full  [3]=health_fail
#define REG_DATA_0    0x08  // rand[31:0]
#define REG_DATA_1    0x0C  // rand[63:32]
#define REG_DATA_2    0x10  // rand[95:64]
#define REG_DATA_3    0x14  // rand[127:96]
#define REG_DATA_4    0x18  // rand[159:128]
#define REG_DATA_5    0x1C  // rand[191:160]
#define REG_DATA_6    0x20  // rand[223:192]
#define REG_DATA_7    0x24  // rand[255:224]
#define REG_COUNT     0x28  // 생성 카운터

// 매크로
#define TRNG_WR(off, val) Xil_Out32(TRNG_BASE + (off), (val))
#define TRNG_RD(off)      Xil_In32(TRNG_BASE + (off))

// ── 256bit 읽기 함수 ───────────────────────────────
int trng_read_256bit(u32 out[8]) {
    u32 status = TRNG_RD(REG_STATUS);

    // FIFO empty 체크
    if (status & 0x02) {
        xil_printf("FIFO empty!\r\n");
        return -1;
    }

    // DATA_0 읽을 때 FIFO pop 발생
    out[0] = TRNG_RD(REG_DATA_0);
    out[1] = TRNG_RD(REG_DATA_1);
    out[2] = TRNG_RD(REG_DATA_2);
    out[3] = TRNG_RD(REG_DATA_3);
    out[4] = TRNG_RD(REG_DATA_4);
    out[5] = TRNG_RD(REG_DATA_5);
    out[6] = TRNG_RD(REG_DATA_6);
    out[7] = TRNG_RD(REG_DATA_7);
    return 0;
}

// ── STATUS 출력 함수 ───────────────────────────────
void trng_print_status(void) {
    u32 s = TRNG_RD(REG_STATUS);
    xil_printf("STATUS: 0x%08X\r\n", s);
    xil_printf("  data_valid  = %d\r\n", (s >> 0) & 1);
    xil_printf("  fifo_empty  = %d\r\n", (s >> 1) & 1);
    xil_printf("  fifo_full   = %d\r\n", (s >> 2) & 1);
    xil_printf("  health_fail = %d\r\n", (s >> 3) & 1);
    xil_printf("  rct_fail    = %d\r\n", (s >> 4) & 1);
    xil_printf("  apt_fail    = %d\r\n", (s >> 5) & 1);
}

// ── 메인 ──────────────────────────────────────────
int main(void) {
    u32 rand_buf[8];
    u32 count;
    int ret;

    xil_printf("\r\n");
    xil_printf("========================================\r\n");
    xil_printf("  256bit TRNG  Zybo Z7-20\r\n");
    xil_printf("  SP 800-90B | AIS-31 PTG.2\r\n");
    xil_printf("========================================\r\n\r\n");

    // ── 1. TRNG 활성화 ──
    xil_printf("1. TRNG enable...\r\n");
    TRNG_WR(REG_CTRL, 0x1);   // enable=1
    usleep(1000000);           // 1초 대기 (FIFO 채워질 때까지)

    // ── 2. STATUS 확인 ──
    xil_printf("2. STATUS 확인\r\n");
    trng_print_status();
    count = TRNG_RD(REG_COUNT);
    xil_printf("   생성된 256bit 워드 수: %d\r\n\r\n", count);

    // health_fail 체크
    if (TRNG_RD(REG_STATUS) & 0x08) {
        xil_printf("*** HEALTH FAIL! 하드웨어 점검 필요 ***\r\n");
        return -1;
    }

    // ── 3. 256bit 랜덤 데이터 10개 출력 ──
    xil_printf("3. 256bit 랜덤 출력 (10개)\r\n");
    xil_printf("-----------------------------------\r\n");

    for (int i = 0; i < 10; i++) {
        // FIFO 찰 때까지 대기
        int timeout = 100000;
        while (TRNG_RD(REG_STATUS) & 0x02) {
            if (--timeout == 0) {
                xil_printf("[%02d] TIMEOUT\r\n", i);
                goto done;
            }
        }

        ret = trng_read_256bit(rand_buf);
        if (ret == 0) {
            // MSB → LSB 순서로 출력
            xil_printf("[%02d] %08X%08X%08X%08X"
                              "%08X%08X%08X%08X\r\n",
                i,
                rand_buf[7], rand_buf[6],
                rand_buf[5], rand_buf[4],
                rand_buf[3], rand_buf[2],
                rand_buf[1], rand_buf[0]);
        }
    }

    // ── 4. NIST용 1Mbit 수집 ──
    xil_printf("\r\n4. NIST SP 800-22 검증용 1Mbit 수집\r\n");
    xil_printf("(4096 x 256bit = 1,048,576 bit)\r\n");
    xil_printf("-----------------------------------\r\n");

    for (int i = 0; i < 4096; i++) {
        int timeout = 1000000;
        while (TRNG_RD(REG_STATUS) & 0x02) {
            if (--timeout == 0) {
                xil_printf("TIMEOUT at %d\r\n", i);
                goto done;
            }
        }

        ret = trng_read_256bit(rand_buf);
        if (ret == 0) {
            // NIST용 hex 출력 (Python에서 수신)
            xil_printf("%08X%08X%08X%08X%08X%08X%08X%08X\r\n",
                rand_buf[7], rand_buf[6],
                rand_buf[5], rand_buf[4],
                rand_buf[3], rand_buf[2],
                rand_buf[1], rand_buf[0]);
        }
    }

done:
    xil_printf("\r\n수집 완료!\r\n");
    xil_printf("PC에서 nist_test.py 실행하세요.\r\n");
    return 0;
}