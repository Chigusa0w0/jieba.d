module jieba.stdseg;

import std.algorithm;
import std.array;
import std.conv : to, text, dtext;
import std.file : readText;
import std.math : log;
import std.regex;
import std.typecons : Yes;
import std.utf : validate;
import jieba.resources;

class StandardTokenizer {
    public:

    private:
    string dictionary;
    int[dstring] freq;
    ulong total;
    ulong maxlen;
    string[string] userWordTags;
    bool initialized;

    public:

    this(string mainDict) {
        dictionary = mainDict;
    }

    string[] cut(string sentence, bool cutAll = false, bool useHmm = true) {
        string[] cutImpl(dstring sentence, bool cutAll, bool useHmm) {
            if (cutAll) {
                return cutImplAll(sentence);
            } else if (useHmm) {
                return cutImplDH(sentence);
            } else {
                return cutImplDwoH(sentence);
            }
        }

        auto tokens = appender!(string[]);
        auto blocks = sentence.splitter!(Yes.keepSeparators)(REGEX_HANIDEFAULT);
        foreach(blk; blocks) {
            if (blk == "") {
                continue;
            }

            if(!blk.matchFirst(REGEX_HANIDEFAULT).empty) {
                auto cuts = cutImpl(blk.dtext, cutAll, useHmm);
                tokens.put(cuts);
            } else {
                auto temp = blk.splitter!(Yes.keepSeparators)(REGEX_SKIPDEFAULT);
                foreach(x; temp) {
                    if (!blk.matchFirst(REGEX_HANIDEFAULT).empty) {
                        tokens.put(x);
                    } else if (!cutAll) {
                        foreach(dch; tokens.dtext) {
                            tokens.put(dch.text);
                        }
                    } else {
                        tokens.put(x);
                    }
                }
            }
        }

        return tokens.array;
    }

    void addWord(string word, int frequency = int.min, string tag = "") {
        initialize();

        auto dword = word.dtext;

        if (frequency == int.min) {
            frequency = suggestFreq(word);
        }

        if (dword in freq) { // Python impl does not handle addition correctly when words repeat / delete words
            total -= freq[dword];
        }

        freq[dword] = frequency;
        total += frequency;
        maxlen = max(maxlen, dword.length);

        if (tag != "") {
            userWordTags[word] = tag;
        }

        for(int i = 0; i < dword.length;) {
            auto frag = dword[0 .. ++i];
            if (frag !in freq) {
                freq[frag] = 0;
            }
        }
    }

    void delWord(string word) {
        addWord(word, 0);
    }

    void loadUserDict(string path) {
        auto content = path.readText;
        content.validate;

        auto matches = content.matchAll(REGEX_USERDICT);
        foreach(match; matches) {
            auto freq = int.min;
            if (match[2] != "") {
                freq = match[2].to!int;
            }

            addWord(match[1], freq, match[3]);
        }
    }

    string[] cutSearch(string sentence, bool useHmm = true) {
        auto words = cut(sentence, false, useHmm);
        auto tokens = appender!(string[]);

        foreach(w; words) {
            auto dw = w.dtext;
            for(int n = 2; n <= maxlen; n++) { // with maxlen, we can yield as many keywords as possible
                if (dw.length > n) {
                    for(int i = 0; i <= dw.length - n; i++) {
                        auto gram = dw[i .. i + n];
                        if (freq.get(gram, 0) > 0) {
                            tokens.put(gram.text);
                        }
                    }
                }
            }
            tokens.put(w);
        }

        return tokens.array;
    }

    private:

    void initialize() {
        if (initialized) return; // fast lane before entering synchronized

        synchronized {
            if (initialized) return; // check again to prevent MT conflict
            
            load(dictionary); // no cache is used currently

            initialized = true;
        }
    }

    pair!(int)[] calc(dstring sentence, int[][] dag) {
        auto n = cast(int) sentence.length;
        auto logtotal = log(total);

        pair!(int)[] route;
        route.length = n + 1;
        route[n] = pair!int(0, 0.0);

        for (auto i = n - 1; i > -1; i--) {
            auto candidate = pair!int(-1, -double.max);
            foreach (x; dag[i])
            {
                auto wfreq = freq.get(sentence[i .. x + 1], 1);
                if (wfreq == 0) {
                    wfreq = 1;
                }

                auto freq = log(wfreq) - logtotal + route[x + 1].freq;
                if (freq > candidate.freq)
                {
                    candidate.freq = freq;
                    candidate.key = x;
                }
            }
            route[i] = candidate;
        }

        return route;
    }

    int[][] getDag(dstring sentence) { // python impl = get_DAG
        initialize();

        auto n = cast(int) sentence.length;

        int[][] dag;
        dag.length = n;

        for(int k = 0; k < n; k++) {
            int[] temp;

            auto i = k;
            auto frag = sentence[k].dtext;

            while ((i < n) && (frag in freq)) {
                if (freq[frag] > 0) {
                    temp ~= i;
                }

                i++;

                frag = sentence[k .. min(i + 1, n)];
            }

            if (temp.length == 0) {
                temp ~= k;
            }

            dag[k] = temp;
        }

        return dag;
    }

    string[] cutImplAll(dstring sentence) { // python impl = __cut_all
        auto dag = getDag(sentence);

        auto lastpos = -1;
        auto tokens = appender!(string[]);
        auto engscan = false;
        auto engbuf = appender!(dchar[]);

        foreach(kk, v; dag) { // int to force size_t -> int conversion
            auto k = cast(long) kk;

            if (engscan && sentence[k].text.matchFirst(REGEX_ENGLISH).empty) {
                engscan = false;
                tokens.put(engbuf.array.text);
            }

            if ((v.length == 1) && (k > lastpos)) {
                auto word = sentence[k .. v[0] + 1];
                if (!word.text.matchFirst(REGEX_ENGLISH).empty) {
                    if (!engscan) {
                        engscan = true;
                        engbuf.clear();
                    }

                    engbuf.put(word);
                }

                if (!engscan) {
                    tokens.put(word.text);
                }

                lastpos = v[0];
            } else {
                foreach(j; v) {
                    if (j > k) {
                        tokens.put(sentence[k .. j + 1].text);
                        lastpos = j;
                    }
                }
            }
        }

        if (engscan) {
            tokens.put(engbuf.array.text);
        }

        return tokens.array;
    }

    string[] cutImplDwoH(dstring sentence) { // python impl = __cut_DAG_NO_HMM
        auto dag = getDag(sentence);
        auto route = calc(sentence, dag);

        auto x = 0;
        auto n = sentence.length;

        auto buf = appender!(dchar[]);
        auto tokens = appender!(string[]);

        while(x < n) {
            auto y = route[x].key + 1;
            auto word = sentence[x .. y];
            if ((y - x == 1) && word.text.match(REGEX_ENGLISH)) {
                buf.put(word);
            } else {
                auto arr = buf.array;
                if (arr.length > 0) {
                    tokens.put(arr.text);
                    buf.clear();
                }

                tokens.put(word.text);
            }

            x = y;
        }

        auto arr = buf.array;
        if (arr.length > 0) {
            tokens.put(arr.text);
            buf.clear();
        }

        return tokens.array;
    }

    string[] cutImplDH(dstring sentence) { // python impl = __cut_DAG
        void bufSeg(ref Appender!(dchar[]) buffer, ref Appender!(string[]) tokens) {
            import jieba.finalseg : finalcut = cut;

            auto buf = buffer.array;

            if (buf.length <= 0) return;

            if (buf.length == 1) {
                tokens.put(buf.text);
            } else if (buf !in freq) {
                auto recognized = finalcut(buf.text);
                foreach(t; recognized) {
                    tokens.put(t);
                }
            } else {
                foreach(ch; buf) {
                    tokens.put(ch.text);
                }
            }

            buffer.clear();
        }

        auto dag = getDag(sentence);
        auto route = calc(sentence, dag);

        auto x = 0;
        auto n = sentence.length;

        auto buf = appender!(dchar[]);
        auto tokens = appender!(string[]);

        while(x < n) {
            auto y = route[x].key + 1;
            auto word = sentence[x .. y];
            if (y - x == 1) {
                buf.put(word);
            } else {
                bufSeg(buf, tokens);

                tokens.put(word.text);
            }

            x = y;
        }

        bufSeg(buf, tokens);

        return tokens.array;
    }

    int suggestFreq(string segment) {
        import std.math : fmax;

        initialize();

        auto ftotal = cast(double) total;
        auto ffreq = 1.0;
        auto cuts = cut(segment, false, false);
        foreach(cut; cuts) {
            ffreq *= freq.get(cut.dtext, 1) / ftotal;
        }
        ffreq = fmax(ffreq * ftotal + 1, cast(double) freq.get(segment.dtext, 1));

        return cast(int) ffreq;
    }

    void load(string path) { // not MT safe/idempotent (total)
        auto content = path.readText;
        content.validate;

        auto matches = content.matchAll(REGEX_USERDICT);
        foreach(match; matches) {
            auto word = match[1].dtext;
            auto ffreq = match[2].to!int;
            
            freq[word] = ffreq;
            total += ffreq;
            maxlen = max(maxlen, word.length);

            for(int i = 0; i < word.length;) {
                auto frag = word[0 .. ++i];
                if (frag !in freq) {
                    freq[frag] = 0;
                }
            }
        }
    }

    private:

    struct pair(T) {
        T key;
        double freq;
    }
}

private:

enum REGEX_USERDICT = regex(`^(.+?)(?:\s+([0-9]+))?(?:\s+([a-z]+))?$`, "m"); // modified regex to parse lines better
enum REGEX_ENGLISH = regex(`[a-zA-Z0-9]`);
enum REGEX_HANIDEFAULT = regex(`([\u4E00-\u9FD5a-zA-Z0-9+#&\._%\-]+)`);
enum REGEX_SKIPDEFAULT = regex(`(\r\n|\s)`);
