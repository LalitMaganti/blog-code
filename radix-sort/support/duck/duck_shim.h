#pragma once
#include <cstdint>
namespace duckdb {
template <class T, class S> inline T UnsafeNumericCast(S s) { return static_cast<T>(s); }
}
#define DUCKDB_EXPLICIT_FALLTHROUGH [[fallthrough]]
