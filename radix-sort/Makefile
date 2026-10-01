CXX := clang++
CPPFLAGS := -I. -Ideps/perfetto -Ideps/perfetto/include -Isupport
CXXFLAGS := -O3 -falign-functions=64
DUCK_FLAGS := -Ideps/duck -Isupport/duck -include support/duck/duck_shim.h
CH_FLAGS := -Isupport/ch -Ideps/ch
ifeq ($(shell uname -s),Darwin)
CH_FLAGS += -DOS_DARWIN
endif

.PHONY: all setup smoke diagnostics clean
all: build/study
setup:
	python3 setup.py
build:
	mkdir -p build
build/study.o: study.cc adapter.h | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(DUCK_FLAGS) -std=c++17 -c $< -o $@
build/ch_adapter.o: ch_adapter.cc adapter.h | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(CH_FLAGS) -std=c++20 -c $< -o $@
build/duck_adapter.o: duck_adapter.cc adapter.h | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(DUCK_FLAGS) -std=c++17 -c $< -o $@
build/study: build/study.o build/ch_adapter.o build/duck_adapter.o
	$(CXX) $^ -o $@
smoke: build/study
	./build/study --smoke
diagnostics: build/test_cost_model build/test_ch_breakdown build/test_duck_verge
build/test_cost_model: diagnostics/test_cost_model.cc | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -std=c++17 $< -o $@
build/test_ch_breakdown: diagnostics/test_ch_breakdown.cc | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(CH_FLAGS) -std=c++20 $< -o $@
build/test_duck_verge: diagnostics/test_duck_verge.cc build/duck_adapter.o | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -std=c++17 $^ -o $@
clean:
	rm -rf build
