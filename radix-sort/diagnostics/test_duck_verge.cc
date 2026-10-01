#include <algorithm>
#include <cstdint>
#include <stdexcept>

#include <cstdio>
#include <vector>
#include <chrono>
#include <algorithm>
#include <random>
#include "adapter.h"

int main() {
    FILE* f = fopen("keys/example_sched_ts_by_cpu.u64", "rb");
    if (!f) throw std::runtime_error("Missing keys/example_sched_ts_by_cpu.u64");
    std::vector<Elem> original(4096);
    for (int i = 0; i < 4096; ++i) {
        fread(&original[i].key, 8, 1, f);
        original[i].pos = i;
        original[i].idx = i;
    }
    fclose(f);

    auto test = [](std::vector<Elem> v, const char* label) {
        double best = 1e30;
        for (int r = 0; r < 50; ++r) {
            auto a = v;
            auto t0 = std::chrono::steady_clock::now();
            DuckDbSort(a.data(), a.data() + a.size());
            auto t1 = std::chrono::steady_clock::now();
            best = std::min(best, std::chrono::duration<double, std::micro>(t1 - t0).count());
        }
        printf("%-20s: %6.1f us\n", label, best);
    };

    test(original, "Original (sorted)");

    auto shuffled = original;
    std::mt19937 g(42);
    std::shuffle(shuffled.begin(), shuffled.end(), g);
    test(shuffled, "Shuffled");

    return 0;
}
