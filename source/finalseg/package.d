module jieba.finalseg;

import std.algorithm;
import std.array;
import std.conv : to, text, dtext;
import std.regex;
import std.typecons : Yes;
import jieba.resources;

auto cut(string sentence) {
    auto blocks = sentence.splitter!(Yes.keepSeparators)(REGEX_HANI);
    auto tokens = appender!(string[]);

    foreach(blk; blocks) {
        if (!blk.matchFirst(REGEX_HANI).empty) {
            auto words = cutImpl(blk.dtext);
            foreach(word; words) {
                if (!ForceSplitWords.canFind(word)) {
                    tokens.put(word);
                } else {
                    foreach(ch; word.dtext) {
                        tokens.put(ch.text);
                    }
                }
            }
        } else {
            auto seg = blk.splitter!(Yes.keepSeparators)(REGEX_SKIP).filter!(x => x != "").array;
            tokens.put(seg);
        }
    }

    return tokens.array;
}

private:

enum MIN_FLOAT = -3.14e100;
enum STATES = [ "B", "M", "S", "E" ];
enum REGEX_HANI = regex(`([\u4E00-\u9FD5]+)`);
enum REGEX_SKIP = regex(`([a-zA-Z0-9]+(?:\.\d+)?%?)`);

enum PREV_STATUS = ([
    "B": [ "E", "S" ],
    "M": [ "M", "B" ],
    "S": [ "S", "E" ],
    "E": [ "B", "M" ]
]);

string[] ForceSplitWords = []; // though ready to use, we hide it from public interfaces

auto cutImpl(dstring sentence) { // python impl = __cut
    auto posLink = viterbi(sentence);
    
    string[] posList;
    for(;;)
    {
        posList ~= posLink.value;

        if (posLink.parent is null) {
            break;
        }

        posLink = *posLink.parent;
    }
    posList = posList.reverse;

    int begin = 0;
    int next = 0;

    auto tokens = appender!(string[]);
    for (auto i = 0; i < sentence.length; i++)
    {
        auto pos = posList[i];
        if (pos == "B") {
            begin = i;
        }
        else if (pos == "E") {
            tokens.put(sentence[begin .. i + 1].text);
            next = i + 1;
        }
        else if (pos == "S") {
            tokens.put(sentence[i].text);
            next = i + 1;
        }
    }
    if (next < sentence.length) {
        tokens.put(sentence[next .. $].text);
    }

    return tokens.array;
}

auto viterbi(dstring sentence) {
    double[string][] V;
    Node[string] path;

    V ~= (double[string]).init;
    foreach(y; STATES) {
        V[0][y] = FINAL_PROB_START[y] + FINAL_PROB_EMIT[y].get(sentence[0].text, MIN_FLOAT);
        path[y] = Node(y, null);
    }

    for(int i = 1; i < sentence.length; i++) {
        auto ch = sentence[i].text;
        V ~= (double[string]).init;

        Node[string] newpath;
        foreach(y; STATES) {
            auto emp = FINAL_PROB_EMIT[y].get(ch, MIN_FLOAT);

            auto prob = -double.max;
            auto state = "";
            foreach (y0; PREV_STATUS[y])
            {
                auto tranp = V[i - 1][y0] + FINAL_PROB_TRANS[y0].get(y, MIN_FLOAT) + emp;
                if (tranp > prob)
                {
                    prob = tranp;
                    state = y0;
                }
            }

            V[i][y] = prob;
            newpath[y] = Node(y, &path[state]);
        }

        path = newpath;
    }

    auto probE = V[$ - 1]["E"];
    auto probS = V[$ - 1]["S"];
    return probE > probS ? path["E"] : path["S"];
}

struct Node {
    string value;
    Node* parent;
}