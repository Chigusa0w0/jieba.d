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
    dstring[dstring] userWordTags;
    bool initialized;

    public:

    this(string mainDict) {
        dictionary = mainDict;
    }

    string[] cut(string sentence, bool cutAll = false, bool useHmm = true) {
        return cut(sentence.dtext, cutAll, useHmm).map!(x => x.text).array;
    }

    string[] cutSearch(string sentence, bool cutAll = false, bool useHmm = true) {
        return cutSearch(sentence.dtext, useHmm).map!(x => x.text).array;
    }

    void addWord(string word, int frequency = int.min, string tag = "") {
        addWord(word.dtext, frequency, tag.dtext);
    }

    void delWord(string word) {
        delWord(word.dtext);
    }

    dstring[] cut(dstring sentence, bool cutAll = false, bool useHmm = true) {
        dstring[] cutImpl(dstring sentence, bool cutAll, bool useHmm) {
            if (cutAll) {
                return cutImplAll(sentence);
            } else if (useHmm) {
                return cutImplDH(sentence);
            } else {
                return cutImplDwoH(sentence);
            }
        }

        auto tokens = appender!(dstring[]);
        auto blocks = sentence.splitter!(Yes.keepSeparators)(REGEX_HANIDEFAULT);
        foreach(blk; blocks) {
            if (blk == "") {
                continue;
            }

            if(!blk.matchFirst(REGEX_HANIDEFAULT).empty) {
                auto cuts = cutImpl(blk, cutAll, useHmm);
                tokens.put(cuts);
            } else {
                auto temp = blk.splitter!(Yes.keepSeparators)(REGEX_SKIPDEFAULT);
                foreach(x; temp) {
                    if (!blk.matchFirst(REGEX_HANIDEFAULT).empty) {
                        tokens.put(x);
                    } else if (!cutAll) {
                        foreach(dch; tokens) {
                            tokens.put(dch);
                        }
                    } else {
                        tokens.put(x);
                    }
                }
            }
        }

        return tokens.array;
    }

    void addWord(dstring word, int frequency = int.min, dstring tag = "") {
        initialize();

        if (frequency == int.min) {
            frequency = suggestFreq(word);
        }

        if (word in freq) { // Python impl does not handle addition correctly when words repeat / delete words
            total -= freq[word];
        }

        freq[word] = frequency;
        total += frequency;
        maxlen = max(maxlen, word.length);

        if (tag != "") {
            userWordTags[word] = tag;
        }

        for(int i = 0; i < word.length;) {
            auto frag = word[0 .. ++i];
            if (frag !in freq) {
                freq[frag] = 0;
            }
        }
    }

    void delWord(dstring word) {
        addWord(word, 0);
    }

    void loadUserDict(string path) {
        auto content = path.readText.dtext;
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

    dstring[] cutSearch(dstring sentence, bool useHmm = true) {
        auto words = cut(sentence, false, useHmm);
        auto tokens = appender!(dstring[]);

        foreach(w; words) {
            auto dw = w;
            for(int n = 2; n <= maxlen; n++) { // with maxlen, we can yield as many keywords as possible
                if (dw.length > n) {
                    for(int i = 0; i <= dw.length - n; i++) {
                        auto gram = dw[i .. i + n];
                        if (freq.get(gram, 0) > 0) {
                            tokens.put(gram);
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
            auto frag = sentence[k .. k + 1];

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

    dstring[] cutImplAll(dstring sentence) { // python impl = __cut_all
        auto dag = getDag(sentence);

        auto lastpos = -1;
        auto tokens = appender!(dstring[]);
        auto engscan = false;
        auto engbuf = appender!(dchar[]);

        foreach(kk, v; dag) { // int to force size_t -> int conversion
            auto k = cast(long) kk;

            if (engscan && sentence[k .. k + 1].matchFirst(REGEX_ENGLISH).empty) {
                engscan = false;
                tokens.put(cast(dstring) engbuf.array);
            }

            if ((v.length == 1) && (k > lastpos)) {
                auto word = sentence[k .. v[0] + 1];
                if (!word.matchFirst(REGEX_ENGLISH).empty) {
                    if (!engscan) {
                        engscan = true;
                        engbuf.clear();
                    }

                    engbuf.put(word);
                }

                if (!engscan) {
                    tokens.put(word);
                }

                lastpos = v[0];
            } else {
                foreach(j; v) {
                    if (j > k) {
                        tokens.put(sentence[k .. j + 1]);
                        lastpos = j;
                    }
                }
            }
        }

        if (engscan) {
            tokens.put(cast(dstring) engbuf.array);
        }

        return tokens.array;
    }

    dstring[] cutImplDwoH(dstring sentence) { // python impl = __cut_DAG_NO_HMM
        auto dag = getDag(sentence);
        auto route = calc(sentence, dag);

        auto x = 0;
        auto n = sentence.length;

        auto buf = appender!(dchar[]);
        auto tokens = appender!(dstring[]);

        while(x < n) {
            auto y = route[x].key + 1;
            auto word = sentence[x .. y];
            if ((y - x == 1) && word.match(REGEX_ENGLISH)) {
                buf.put(word);
            } else {
                auto arr = cast(dstring) buf.array;
                if (arr.length > 0) {
                    tokens.put(arr);
                    buf.clear();
                }

                tokens.put(word);
            }

            x = y;
        }

        auto arr = cast(dstring) buf.array;
        if (arr.length > 0) {
            tokens.put(arr);
            buf.clear();
        }

        return tokens.array;
    }

    dstring[] cutImplDH(dstring sentence) { // python impl = __cut_DAG
        void bufSeg(ref Appender!(dchar[]) buffer, ref Appender!(dstring[]) tokens) {
            import jieba.finalseg : finalcut = cut;

            auto buf = cast(dstring) buffer.array;

            if (buf.length <= 0) return;

            if (buf.length == 1) {
                tokens.put(buf);
            } else if (buf !in freq) {
                auto recognized = finalcut(buf);
                foreach(t; recognized) {
                    tokens.put(t);
                }
            } else {
                foreach(ch; buf) {
                    tokens.put(ch.dtext);
                }
            }

            buffer.clear();
        }

        auto dag = getDag(sentence);
        auto route = calc(sentence, dag);

        auto x = 0;
        auto n = sentence.length;

        auto buf = appender!(dchar[]);
        auto tokens = appender!(dstring[]);

        while(x < n) {
            auto y = route[x].key + 1;
            auto word = sentence[x .. y];
            if (y - x == 1) {
                buf.put(word);
            } else {
                bufSeg(buf, tokens);

                tokens.put(word);
            }

            x = y;
        }

        bufSeg(buf, tokens);

        return tokens.array;
    }

    int suggestFreq(dstring segment) {
        import std.math : fmax;

        initialize();

        auto ftotal = cast(double) total;
        auto ffreq = 1.0;
        auto cuts = cut(segment, false, false);
        foreach(cut; cuts) {
            ffreq *= freq.get(cut, 1) / ftotal;
        }
        ffreq = fmax(ffreq * ftotal + 1, cast(double) freq.get(segment, 1));

        return cast(int) ffreq;
    }

    void load(string path) { // not MT safe/idempotent (total)
        auto content = path.readText.dtext;
        content.validate;

        auto matches = content.matchAll(REGEX_USERDICT);
        foreach(match; matches) {
            auto word = match[1];
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

enum REGEX_USERDICT = regex(`^(.+?)(?:\s+([0-9]+))?(?:\s+([a-z]+))?$`d, "m"); // modified regex to parse lines better
enum REGEX_ENGLISH = regex(`[a-zA-Z0-9]`d);
enum REGEX_HANIDEFAULT = regex(`([\u4E00-\u9FD5a-zA-Z0-9+#&\._%\-]+)`d);
enum REGEX_SKIPDEFAULT = regex(`(\r\n|\s)`d);
