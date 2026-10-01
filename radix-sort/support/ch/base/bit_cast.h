#pragma once
#include <cstring>
template <typename To, typename From>
To bit_cast(const From & from) { To to; static_assert(sizeof(To) == sizeof(From)); std::memcpy(&to, &from, sizeof(To)); return to; }
