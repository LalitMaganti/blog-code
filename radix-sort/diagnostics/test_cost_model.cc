#include <algorithm>
#include <cstdint>
#include <stdexcept>

#include <cstdio>
#include <vector>
#include <chrono>
#include <cstring>

struct E { uint64_t key; uint32_t pos; uint32_t idx; };

int main() {
    std::vector<uint32_t> counts(65536);
    double t_memset = 1e30;
    for (int r = 0; r < 200; ++r) {
        auto t0 = std::chrono::steady_clock::now();
        memset(counts.data(), 0, 65536 * sizeof(uint32_t));
        auto t1 = std::chrono::steady_clock::now();
        asm volatile("" : : "r"(counts.data()) : "memory");
        t_memset = std::min(t_memset, std::chrono::duration<double, std::micro>(t1 - t0).count());
    }

    double t_prefix = 1e30;
    for (int r = 0; r < 200; ++r) {
        auto t0 = std::chrono::steady_clock::now();
        uint32_t sum = 0;
        for (int i = 0; i < 65536; ++i) {
            uint32_t x = counts[i];
            counts[i] = sum;
            sum += x;
        }
        auto t1 = std::chrono::steady_clock::now();
        asm volatile("" : : "r"(counts.data()) : "memory");
        t_prefix = std::min(t_prefix, std::chrono::duration<double, std::micro>(t1 - t0).count());
    }
    printf("memset 65536 counts (256 KB) : %5.2f us\n", t_memset);
    printf("prefix sum 65536 counts       : %5.2f us\n", t_prefix);
    printf("Total 16-bit bucket overhead  : %5.2f us\n", t_memset + t_prefix);

    for (size_t n : {1024, 4096, 16384, 65536, 262144}) {
        std::vector<E> src(n), dst(n);
        for (size_t i = 0; i < n; ++i) src[i] = {i, (uint32_t)i, 0};
        double t_copy = 1e30;
        for (int r = 0; r < 200; ++r) {
            auto t0 = std::chrono::steady_clock::now();
            // In radix sort scatter: dst[c[bucket]++] = src[i]
            for (size_t i = 0; i < n; ++i) {
                dst[i] = src[i];
            }
            auto t1 = std::chrono::steady_clock::now();
            asm volatile("" : : "r"(dst.data()) : "memory");
            t_copy = std::min(t_copy, std::chrono::duration<double, std::micro>(t1 - t0).count());
        }
        printf("scatter/move %6zu elements : %6.2f us (ns/elem: %4.1f)\n",
               n, t_copy, (t_copy * 1000.0) / n);
    }
    return 0;
}
