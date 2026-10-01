#include <algorithm>
#include <cstdint>
#include <stdexcept>

#include <cstdio>
#include <vector>
#include <chrono>
#include <numeric>
#include <Columns/RadixSortHelper.h>
#include <base/sort.h>
#include "adapter.h"

int main() {
    FILE* f = fopen("keys/chrome_slice_name.u64", "rb");
    if (!f) throw std::runtime_error("Missing keys/chrome_slice_name.u64");
    fseek(f, 0, SEEK_END);
    size_t bytes = ftell(f);
    fseek(f, 0, SEEK_SET);
    size_t n = bytes / 8;
    std::vector<UInt64> data(n);
    fread(data.data(), 8, n, f);
    fclose(f);

    printf("chrome_slice_name: n = %zu\n", n);

    std::vector<size_t> res(n);
    auto less_stable = [&](size_t a, size_t b) { return data[a] < data[b] || (data[a] == data[b] && a < b); };

    // 1. Benchmark trySort alone
    double t_trysort = 1e30;
    for (int r = 0; r < 5; ++r) {
        std::iota(res.begin(), res.end(), size_t{0});
        auto t0 = std::chrono::steady_clock::now();
        bool ok = trySort(res.begin(), res.end(), less_stable);
        auto t1 = std::chrono::steady_clock::now();
        t_trysort = std::min(t_trysort, std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    printf("  trySort alone (failed): %6.2f ms\n", t_trysort);

    // 2. Benchmark RadixSort executeLSD on UInt64 (8 passes)
    std::vector<DB::ValueWithIndex<UInt64>> pairs64(n);
    for (UInt32 i = 0; i < static_cast<UInt32>(n); ++i) pairs64[i] = {data[i], i};
    double t_radix64 = 1e30;
    for (int r = 0; r < 5; ++r) {
        auto p = pairs64;
        auto t0 = std::chrono::steady_clock::now();
        RadixSort<DB::RadixSortTraits<UInt64>>::executeLSD(p.data(), n, false, res.data());
        auto t1 = std::chrono::steady_clock::now();
        t_radix64 = std::min(t_radix64, std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    printf("  RadixSort UInt64 (8 passes): %6.2f ms\n", t_radix64);

    // 3. Benchmark RadixSort executeLSD on UInt16 (2 passes)
    std::vector<DB::ValueWithIndex<UInt16>> pairs16(n);
    for (UInt32 i = 0; i < static_cast<UInt32>(n); ++i) pairs16[i] = {static_cast<UInt16>(data[i]), i};
    double t_radix16 = 1e30;
    for (int r = 0; r < 5; ++r) {
        auto p = pairs16;
        auto t0 = std::chrono::steady_clock::now();
        RadixSort<DB::RadixSortTraits<UInt16>>::executeLSD(p.data(), n, false, res.data());
        auto t1 = std::chrono::steady_clock::now();
        t_radix16 = std::min(t_radix16, std::chrono::duration<double, std::milli>(t1 - t0).count());
    }
    printf("  RadixSort UInt16 (2 passes): %6.2f ms (%.2fx faster than UInt64!)\n",
           t_radix16, t_radix64 / t_radix16);

    return 0;
}
