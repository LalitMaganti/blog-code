#pragma once
#include <cstddef>
#include <cstdint>
#include <vector>
struct Elem { uint64_t key; uint32_t pos; uint32_t idx; };
// DuckDB's small-partition fallback compares whole sort keys; here the key.
inline bool operator<(const Elem & a, const Elem & b) { return a.key < b.key; }
void ClickHouseSort(const Elem * in, size_t n);
extern std::vector<size_t> g_ch_perm;
void DuckDbSort(Elem * begin, Elem * end);
