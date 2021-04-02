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

private:

import std.traits : isSomeString;
import asdf;

mixin template JsonResourceLoader(T, alias resname) if (isSomeString!(typeof(resname))) {
    enum string RAW = import(resname ~ ".json");
    shared static immutable T RES;
    shared static this() {
        RES = RAW.deserialize!(T);
    }
    alias RES this;
}