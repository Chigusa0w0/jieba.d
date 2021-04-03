module jieba.resources;

static class FINAL_PROB_EMIT {
    mixin JsonResourceLoader!(double[string][string], `final_prob_emit`);
}

static class FINAL_PROB_START {
    mixin JsonResourceLoader!(double[string], `final_prob_start`);
}

static class FINAL_PROB_TRANS {
    mixin JsonResourceLoader!(double[string][string], `final_prob_trans`);
}

static class POS_PROB_EMIT {
    mixin JsonResourceLoader!(double[string][string], `pos_prob_emit`);
}

static class POS_PROB_START {
    mixin JsonResourceLoader!(double[string], `pos_prob_start`);
}

static class POS_PROB_TRANS {
    mixin JsonResourceLoader!(double[string][string], `pos_prob_trans`);
}

static class POS_CHAR_STATE_TAB {
    mixin JsonResourceLoader!(string[][string], `pos_char_state_tab`);
}

version(unittest) static class UNITTEST_DICT {
    mixin TextResourceLoader!(dstring, `unittest_dict`);
}

private:

import std.conv : to;
import std.traits : isSomeString;
import asdf;

mixin template JsonResourceLoader(T, string resname) {
    enum string RAW = import(resname ~ ".json");
    static immutable T RES;
    shared static this() {
        RES = RAW.deserialize!(T);
    }
    alias RES this;
}

mixin template TextResourceLoader(T, string resname) {
    enum string RAW = import(resname ~ ".txt");
    static immutable T RES;
    shared static this() {
        RES = RAW.to!T;
    }
    alias RES this;
}
