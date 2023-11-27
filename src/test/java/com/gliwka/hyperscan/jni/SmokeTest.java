package com.gliwka.hyperscan.jni;

import org.bytedeco.javacpp.*;
import org.bytedeco.javacpp.annotation.Cast;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static com.gliwka.hyperscan.jni.hyperscan.*;
import static org.assertj.core.api.Assertions.assertThat;

class SmokeTest {
    @Test
    void smokeTest() {
        assertThat(hs_valid_platform()).isEqualTo(0);

        String[] patterns = { "abc1", "asa", "dab" };
        PointerPointer<BytePointer> expressionsPointer = new PointerPointer<>(patterns);
        IntPointer patternIds = new IntPointer(1, 2, 3);
        IntPointer compileFlags = new IntPointer(HS_FLAG_SOM_LEFTMOST, HS_FLAG_SOM_LEFTMOST, HS_FLAG_SOM_LEFTMOST);

        PointerPointer<hs_database_t> database_t_p = new PointerPointer<hs_database_t>(1);
        PointerPointer<hs_compile_error_t> compile_error_t_p = new PointerPointer<hs_compile_error_t>(1);


        int compileResult = hs_compile_multi(expressionsPointer, compileFlags, patternIds, 3, HS_MODE_BLOCK,
                    null, database_t_p, compile_error_t_p);
        assertThat(0).isEqualTo(compileResult);

        hs_database_t database_t = new hs_database_t(database_t_p.get(0));
        hs_scratch_t scratchSpace = new hs_scratch_t();
        int allocResult = hyperscan.hs_alloc_scratch(database_t, scratchSpace);
        assertThat(0).isEqualTo(allocResult);

        List<long[]> matches = new ArrayList<>();

        match_event_handler matchEventHandler = new match_event_handler() {
            @Override
            public int call(@Cast("unsigned int") int id,
                            @Cast("unsigned long long") long from,
                            @Cast("unsigned long long") long to,
                            @Cast("unsigned int") int flags, Pointer context) {
                matches.add(new long[] {id, from, to});
                return 0;
            }
        };

        String textToSearch = "-21dasaaadabcaaa";
        hs_scan(database_t, textToSearch, textToSearch.length(), 0, scratchSpace, matchEventHandler, expressionsPointer);
        assertThat(matches).containsExactly(new long[] {2, 4, 7}, new long[] {3, 9, 12});
    }
}