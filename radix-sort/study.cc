// Radix sort digit-width study: sorts the same keys with several strategies,
// checks each against std::stable_sort, and prints the best time of several
// runs.
//
// Usage: study [--real <dir>] [--synthetic]
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <functional>
#include <stdexcept>
#include <memory>
#include <random>
#include <string>
#include <utility>
#include <vector>

#include <dirent.h>

#include "src/trace_processor/core/util/sort.h"
#include "adapter.h"
#include "duck_shim.h"
#include "ska_sort.hpp"

namespace core = perfetto::trace_processor::core;

struct E {
  uint64_t key;
  uint32_t pos;
  uint32_t idx;
};
static_assert(sizeof(E) == 16);
inline bool operator<(const E&a,const E&b){return a.key<b.key;}

inline bool Less(const E& a, const E& b) {
  return a.key != b.key ? a.key < b.key : a.pos < b.pos;
}

uint32_t Log2(size_t n) {
  return 64 - __builtin_clzll(n);
}

// ---------------------------------------------------------------- strategies

// Comparison sort: the toolchain standard library sort on (key, position).
E* Comparison(E* b, E* e, E*, uint32_t) {
  std::sort(b, e, Less);
  return b;
}

// Ours: StableSortByKey from sort.h (adaptive digits, std::sort fallback).
E* Ours(E* b, E* e, E* scratch, uint32_t key_bits) {
  return core::StableSortByKey(
      b, e, scratch, key_bits, [](const E& x) { return x.key; },
      [](const E& x) { return x.pos; });
}

// Generic LSD radix with all digit histograms in one read and uniform-digit
// pass skipping, with `bits`-wide digits. Optional software write-combining.
template <bool kWriteCombine>
E* Lsd(E* b, E* e, E* scratch, uint32_t key_bits, uint32_t max_bits) {
  size_t n = e - b;
  if (n <= 1 || key_bits == 0) return b;
  uint32_t passes = (key_bits + max_bits - 1) / max_bits;
  uint32_t bits = (key_bits + passes - 1) / passes;
  size_t buckets = size_t{1} << bits;
  uint64_t mask = buckets - 1;
  std::vector<uint32_t> counts(passes * buckets);
  for (E* it = b; it != e; ++it) {
    for (uint32_t p = 0; p < passes; ++p)
      ++counts[p * buckets + ((it->key >> (p * bits)) & mask)];
  }
  // Write-combining: per bucket, a 64-byte line of 4 elements in L1, flushed
  // whole to the destination.
  constexpr uint32_t kLine = 4;
  std::vector<E> wc_buf;
  std::vector<uint8_t> wc_fill;
  if (kWriteCombine) {
    wc_buf.resize(buckets * kLine);
    wc_fill.resize(buckets);
  }
  E* src = b;
  E* dst = scratch;
  for (uint32_t p = 0; p < passes; ++p) {
    uint32_t* c = counts.data() + p * buckets;
    uint32_t shift = p * bits;
    if (c[(src->key >> shift) & mask] == n) continue;
    uint32_t t = 0;
    for (size_t d = 0; d < buckets; ++d) {
      uint32_t x = c[d];
      c[d] = t;
      t += x;
    }
    if (!kWriteCombine) {
      for (E* it = src; it != src + n; ++it)
        dst[c[(it->key >> shift) & mask]++] = *it;
    } else {
      std::fill(wc_fill.begin(), wc_fill.end(), 0);
      E* buf = wc_buf.data();
      uint8_t* fill = wc_fill.data();
      for (E* it = src; it != src + n; ++it) {
        size_t d = (it->key >> shift) & mask;
        buf[d * kLine + fill[d]] = *it;
        if (++fill[d] == kLine) {
          memcpy(dst + c[d], buf + d * kLine, sizeof(E) * kLine);
          c[d] += kLine;
          fill[d] = 0;
        }
      }
      for (size_t d = 0; d < buckets; ++d) {
        memcpy(dst + c[d], buf + d * kLine, sizeof(E) * fill[d]);
        c[d] += fill[d];
      }
    }
    std::swap(src, dst);
  }
  return src;
}

// Fixed-digit LSD with a comparison-sort fallback below `small` elements:
// the shape of engines which fix the digit width (e.g. 8 bits).
uint32_t g_fixed_bits = 8;
size_t g_fixed_small = 256;
E* FixedLsd(E* b, E* e, E* scratch, uint32_t key_bits) {
  if (size_t(e - b) < g_fixed_small) return Comparison(b, e, scratch, key_bits);
  return Lsd<false>(b, e, scratch, key_bits, g_fixed_bits);
}

// Ours before this change: fixed 16-bit digits, with the cost model of the
// time deciding radix vs std::sort.
E* Ours16(E* b, E* e, E* scratch, uint32_t key_bits) {
  size_t n = e - b;
  uint64_t passes = (key_bits + 15) / 16;
  uint64_t bits = passes ? (key_bits + passes - 1) / passes : 0;
  uint64_t radix = passes * 3 * n + (passes << bits);
  if (!(radix < 2 * n * uint64_t{Log2(n)})) return Comparison(b, e, scratch, key_bits);
  return Lsd<false>(b, e, scratch, key_bits, 16);
}

// Ours with each element weighted `g_c` times a count in the digit choice and
// in the radix-vs-comparison decision.
uint64_t g_c = 4;
E* OursC(E* b, E* e, E* scratch, uint32_t key_bits) {
  size_t n = e - b;
  if (n <= 1 || key_bits == 0) return b;
  uint32_t fewest = (key_bits + 15) / 16;
  uint32_t best_p = 0;
  uint64_t best = UINT64_MAX;
  for (uint32_t p = fewest; p <= fewest + 2; ++p) {
    uint32_t bits = (key_bits + p - 1) / p;
    uint64_t cost = uint64_t{p} * (g_c * n + (uint64_t{1} << bits));
    if (cost < best) { best = cost; best_p = p; }
  }
  if (!(best < 2 * g_c / 3 * n * uint64_t{Log2(n)} * 3 / 2))
    return Comparison(b, e, scratch, key_bits);
  return Lsd<false>(b, e, scratch, key_bits, (key_bits + best_p - 1) / best_p);
}

E* Lsd11(E* b, E* e, E* scratch, uint32_t key_bits) {
  if (size_t(e - b) < 256) return Comparison(b, e, scratch, key_bits);
  return Lsd<false>(b, e, scratch, key_bits, 11);
}
E* Wc11(E* b, E* e, E* scratch, uint32_t key_bits) {
  if (size_t(e - b) < 256) return Comparison(b, e, scratch, key_bits);
  return Lsd<true>(b, e, scratch, key_bits, 11);
}

// Narrow digits with write-combining, as the literature does.
uint32_t g_wc_bits = 8;
E* WriteCombined(E* b, E* e, E* scratch, uint32_t key_bits) {
  if (size_t(e - b) < 256) return Comparison(b, e, scratch, key_bits);
  return Lsd<true>(b, e, scratch, key_bits, g_wc_bits);
}

// MSD radix on 8-bit digits from the most significant varying byte, stable
// (counting sort into scratch, copied back), with a comparison sort for small
// buckets: the shape of DuckDB's sort.
size_t g_msd_small = 24;
void MsdRec(E* b, E* e, E* scratch, int shift) {
  size_t n = e - b;
  if (n < g_msd_small || shift < 0) {
    std::sort(b, e, Less);
    return;
  }
  uint32_t count[257] = {};
  for (E* it = b; it != e; ++it) ++count[((it->key >> shift) & 0xff) + 1];
  if (count[((b->key >> shift) & 0xff) + 1] == n) {
    MsdRec(b, e, scratch, shift - 8);
    return;
  }
  for (int d = 0; d < 256; ++d) count[d + 1] += count[d];
  uint32_t at[256];
  memcpy(at, count, sizeof(at));
  for (E* it = b; it != e; ++it) scratch[at[(it->key >> shift) & 0xff]++] = *it;
  memcpy(b, scratch, n * sizeof(E));
  for (int d = 0; d < 256; ++d) {
    if (count[d + 1] - count[d] > 1)
      MsdRec(b + count[d], b + count[d + 1], scratch + count[d], shift - 8);
  }
}
E* Msd(E* b, E* e, E* scratch, uint32_t key_bits) {
  if (key_bits == 0) return b;
  int top = int((key_bits + 7) / 8) * 8 - 8;
  MsdRec(b, e, scratch, top);
  return b;
}

// ---------------------------------------------------------------- harness

// How a strategy's output is checked.
enum class Output {
  kStable,       // Sorted elements, equal keys in input order.
  kPermutation,  // A row permutation (g_ch_perm), in stable order.
  kUnstable,     // Sorted elements in place, equal keys in any order.
};

struct Strategy {
  const char* name;
  E* (*fn)(E*, E*, E*, uint32_t);
  Output output = Output::kStable;
};

E* ClickHouse(E* b, E* e, E*, uint32_t) {
  ClickHouseSort(reinterpret_cast<const Elem*>(b), e - b);
  return nullptr;
}
E* DuckDb(E* b, E* e, E*, uint32_t) {
  DuckDbSort(reinterpret_cast<Elem*>(b), reinterpret_cast<Elem*>(e));
  return b;
}

// Bounds supplied by the benchmark, modelling optimizer statistics.
uint64_t compressed_min = 0;
uint32_t compressed_bytes = 8;
struct CompressedExtract {
  using result_type = uint64_t;
  const uint64_t& operator()(const E& e) const { return e.key; }
  bool ByteIsSkippable(const size_t& off) const { return off == 0; }
  bool Interrupted() const { return false; }
  bool requires_next_sort = false;
  size_t ska_sort_width;
};
E* DuckCompressed(E* b, E* e, E*, uint32_t) {
  if (compressed_bytes == 8) return DuckDb(b,e,nullptr,0);
  const uint32_t shift = 8 * (7 - compressed_bytes);
  const uint64_t mask = (uint64_t{1} << (8 * compressed_bytes)) - 1;
  for (E* it=b;it!=e;++it) it->key=((it->key-compressed_min)<<shift)|(uint64_t{1}<<56);
  CompressedExtract ex;ex.ska_sort_width=compressed_bytes+1;
  auto fallback=[ex](E* first,E* last){duckdb_ska_sort::ska_sort(first,last,ex);};
  duckdb_vergesort::vergesort(b,e,[](const E&a,const E&b){return a.key<b.key;},fallback);
  for (E* it=b;it!=e;++it) it->key=((it->key>>shift)&mask)+compressed_min;
  return b;
}

// Narrows keys to the bytes below the highest which varies, as SortRowLayout
// does, and returns the key width in bits.
uint32_t Narrow(std::vector<E>& v) {
  uint64_t diff = 0;
  for (const E& x : v) diff |= x.key ^ v[0].key;
  uint32_t bits = diff ? 64 - __builtin_clzll(diff) : 0;
  bits = (bits + 7) / 8 * 8;
  uint64_t mask = bits == 64 ? ~0ull : (1ull << bits) - 1;
  for (E& x : v) x.key &= mask;
  return bits;
}

bool any_failure = false;

void Run(const char* name, std::vector<uint64_t> keys,
         const std::vector<Strategy>& strategies) {
  size_t n = keys.size();
  if (n == 0) throw std::runtime_error("Empty key input");
  std::vector<E> in(n);
  for (size_t i = 0; i < n; ++i) in[i] = {keys[i], uint32_t(i), uint32_t(i)};
  uint32_t kb = Narrow(in);
  auto bounds=std::minmax_element(in.begin(),in.end(),[](const E&a,const E&b){return a.key<b.key;});
  compressed_min=bounds.first->key;
  uint64_t range=bounds.second->key-compressed_min;
  compressed_bytes=range<=UINT8_MAX?1:range<=UINT16_MAX?2:range<=UINT32_MAX?4:8;
  std::vector<E> expected = in;
  std::stable_sort(expected.begin(), expected.end(),
                   [](const E& a, const E& b) { return a.key < b.key; });
  std::vector<E> a(n), s(n);
  int reps = n <= 65536 ? 12 : 5;
  printf("%-28s %8zu %3u", name, n, kb);
  for (const Strategy& st : strategies) {
    double best = 1e30;
    bool ok = true;
    for (int r = -1; r < reps; ++r) {
      a = in;
      auto t0 = std::chrono::steady_clock::now();
      E* out = st.fn(a.data(), a.data() + n, s.data(), kb);
      auto t1 = std::chrono::steady_clock::now();
      if (r >= 0) best = std::min(best, std::chrono::duration<double, std::micro>(t1 - t0).count());
      if (r == 0) {
        if (st.output == Output::kPermutation) {
          for (size_t i = 0; i < n; ++i) s[i] = a[g_ch_perm[i]];
          out = s.data();
        }
        std::vector<bool> seen(n);
        for (size_t i = 0; i < n && ok; ++i) {
          ok = out[i].key == expected[i].key;
          if (st.output != Output::kUnstable) ok = ok && out[i].pos == expected[i].pos;
          ok = ok && out[i].pos < n && out[i].idx == out[i].pos;
          if (!ok) break;
          ok = ok && !seen[out[i].pos];
          seen[out[i].pos] = true;
        }
      }
    }
    any_failure |= !ok;
    printf(" %10.1f%s", best, ok ? "" : "!");
  }
  printf("\n");
  fflush(stdout);
}

std::vector<uint64_t> Load(const std::string& path) {
  FILE* f = fopen(path.c_str(), "rb");
  std::vector<uint64_t> v;
  if (!f) throw std::runtime_error("Cannot read " + path);
  uint64_t x;
  while (fread(&x, 8, 1, f) == 1) v.push_back(x);
  fclose(f);
  return v;
}

int main(int argc, char** argv) {
  std::vector<Strategy> strategies = {
      {"comparison", Comparison},
      {"ours16", Ours16},
      {"ours", Ours},
      {"fixed8", FixedLsd},
      {"msd8", Msd},
      {"lsd11", Lsd11},
      {"wc11", Wc11},
      {"clickhouse", ClickHouse, Output::kPermutation},
      {"duckdb", DuckDb, Output::kUnstable},
      {"duck_comp", DuckCompressed, Output::kUnstable},
  };
  printf("%-28s %8s %3s", "dataset", "n", "kb");
  for (const Strategy& st : strategies) printf(" %10s", st.name);
  printf("   (us, best of runs; ! = wrong order)\n");
  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    if (arg == "--real" && i + 1 < argc) {
      std::string dir = argv[++i];
      std::vector<std::string> files;
      DIR* d = opendir(dir.c_str());
      if (!d) throw std::runtime_error("Cannot open " + dir);
      while (dirent* ent = readdir(d)) {
        std::string f = ent->d_name;
        if (f.size() > 4 && f.substr(f.size() - 4) == ".u64") files.push_back(f);
      }
      closedir(d);
      std::sort(files.begin(), files.end());
      for (const std::string& f : files) {
        std::vector<uint64_t> keys = Load(dir + "/" + f);
        std::string base = f.substr(0, f.size() - 4);
        for (size_t n : {size_t{4096}, size_t{65536}}) {
          if (n < keys.size())
            Run((base + "/" + std::to_string(n)).c_str(),
                std::vector<uint64_t>(keys.begin(), keys.begin() + n), strategies);
        }
        Run(base.c_str(), keys, strategies);
      }
    } else if (arg == "--synthetic" || arg == "--smoke") {
      std::mt19937_64 rnd(1);
      for (size_t n : {size_t{1024}, size_t{16384}, size_t{262144}, size_t{4} << 20}) {
        if (arg == "--smoke" && n > 16384) continue;
        for (uint32_t kb : {32u, 64u}) {
          uint64_t m = kb == 64 ? ~0ull : (1ull << kb) - 1;
          std::vector<uint64_t> random(n), golden(n), dup(n);
          for (size_t j = 0; j < n; ++j) {
            random[j] = rnd() & m;
            golden[j] = (uint64_t(j) * 0x9E3779B97F4A7C15ull) >> (64 - kb);
            dup[j] = (rnd() % 16) * (m / 16);
          }
          std::string sfx = "/" + std::to_string(n) + "/" + std::to_string(kb);
          Run(("random" + sfx).c_str(), random, strategies);
          Run(("golden" + sfx).c_str(), golden, strategies);
          Run(("dup16" + sfx).c_str(), dup, strategies);
        }
      }
    }
  }
  return any_failure ? 1 : 0;
}
