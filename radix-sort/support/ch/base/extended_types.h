#pragma once
#include <cstdint>
#include <type_traits>
using UInt8 = uint8_t; using UInt16 = uint16_t; using UInt32 = uint32_t; using UInt64 = uint64_t;
using Int8 = int8_t; using Int16 = int16_t; using Int32 = int32_t; using Int64 = int64_t;
using Float32 = float; using Float64 = double;
template <class T> using make_unsigned_t = std::make_unsigned_t<T>;
template <class T> inline constexpr bool is_signed_v = std::is_signed_v<T>;
template <class T> inline constexpr bool is_integer = std::is_integral_v<T>;
template <class T> inline constexpr bool is_arithmetic_v = std::is_arithmetic_v<T>;
template <class T> inline constexpr bool is_floating_point = std::is_floating_point_v<T>;
namespace DB { using ::UInt8; using ::UInt16; using ::UInt32; using ::UInt64; using ::Int8; using ::Int16; using ::Int32; using ::Int64; }
template <class T> inline constexpr bool is_unsigned_v = std::is_unsigned_v<T>;
#ifndef ALWAYS_INLINE
#define ALWAYS_INLINE __attribute__((__always_inline__))
#endif
#ifndef NO_INLINE
#define NO_INLINE __attribute__((__noinline__))
#endif
#ifndef chassert
#define chassert(x) ((void)0)
#endif
