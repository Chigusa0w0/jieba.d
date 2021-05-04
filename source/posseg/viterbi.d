module jieba.posseg.viterbi;

import std.algorithm;
import std.array;
import std.conv : text;
import jieba.resources;

auto viterbi(dstring sentence, out double probLast) @trusted {
    double[string][] V;
    string[string][] path;

    V ~= (double[string]).init;
    path ~= (string[string]).init;
    auto allStates = POS_PROB_TRANS.keys;
    auto ally = (cast(string[][string]) POS_CHAR_STATE_TAB).get(sentence[0].text, allStates);
    foreach(y; ally) {
        V[0][y] = POS_PROB_START[y] + POS_PROB_EMIT[y].get(sentence[0].text, MIN_FLOAT);
        path[0][y] = "";
    }

    for(int i = 1; i < sentence.length; i++) {
        auto ch = sentence[i].text;
        V ~= (double[string]).init;
        path ~= (string[string]).init;

        string[] prevStates = path[i - 1].keys.filter!(x => POS_PROB_TRANS[x].length > 0).array;
        string[] expectNext = prevStates.map!(x => POS_PROB_TRANS[x].keys).fold!((x, y) => x ~ y).array.sort.array;
        string[] obsState = (cast(string[][string]) POS_CHAR_STATE_TAB).get(ch, allStates).sort.array;
        obsState = setIntersection(obsState, expectNext).array;

        if(obsState.length == 0) {
            obsState = (expectNext.length > 0) ? expectNext : allStates;
        }

        foreach(y; obsState) {
            auto emp = POS_PROB_EMIT[y].get(ch, MIN_FLOAT);

            auto prob = -double.max;
            auto state = "";
            foreach (y0; prevStates)
            {
                auto tranp = V[i - 1][y0] + POS_PROB_TRANS[y0].get(y, -double.infinity) + emp;
                if (tranp > prob || ((tranp == prob) && (y0 > state)))
                {
                    prob = tranp;
                    state = y0;
                }
            }

            V[i][y] = prob;
            path[i][y] = state;
        }
    }

    probLast = -double.max;
    auto stateLast = "";
    auto vLast = V[$ - 1];
    foreach(y1; path[$ - 1].keys) {
        auto tranp = vLast[y1];
        if (tranp > probLast || ((tranp == probLast) && (y1 > stateLast)))
        {
            probLast = tranp;
            stateLast = y1;
        }
    }

    string[] route;
    route.length = sentence.length;
    int i = cast(int)sentence.length - 1;
    while(i >= 0) {
        route[i] = stateLast;
        stateLast = path[i][stateLast];
        i--;
    }

    return route;
}

private:

enum MIN_FLOAT = -3.14e100;