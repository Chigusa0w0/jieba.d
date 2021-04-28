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

/**
 * Standard sentence segmenter implementation.
 * This segmenter uses corpus word frequencies to segment sentences.
 * For words corpus do not cover, the Viterbi algorithm is used to infer the word segmentation.
 * This segmenter does not tag words.
 *
 * See_Also: `jieba.finalseg`, `jieba.posseg`
 */
class StandardSegmenter {
    public:

    private:
    string dictionary;
    int[dstring] freq;
    ulong total;
    ulong maxlen;
    dstring[dstring] userWordTags;
    bool initialized;

    public:

    /**
     * Construct a `StandardTokenizer` with given main dictionary.
     *
     * Params:
     *     mainDict = Path to the main dictionary.
     */
    this(string mainDict) @safe {
        dictionary = mainDict;
    }

    /**
     * Segments a Chinese sentence into separated words.
     *
     * Params:
     *     sentence = The string to be segmented.
     *     cutAll =   Model type. True for full pattern, False for accurate pattern.
     *     useHmm =   Whether to use the Hidden Markov Model.
     *
     * Returns:
     *     An array containing all segments of the `sentence`.
     */
    string[] cut(string sentence, bool cutAll = false, bool useHmm = true) @safe {
        return cut(sentence.dtext, cutAll, useHmm).map!(x => x.text).array;
    }

    /**
     * Extract all words from a Chinese sentence.
     * This method will extract as many words as possible, some of which may have overlapping parts.
     *
     * Params:
     *     sentence = The string to be segmented.
     *     useHmm =   Whether to use the Hidden Markov Model.
     *
     * Returns:
     *     An array containing all segments of the `sentence`.
     */
    string[] cutSearch(string sentence, bool cutAll = false, bool useHmm = true) @safe {
        return cutSearch(sentence.dtext, useHmm).map!(x => x.text).array;
    }

    /**
     * Add a single word into current dictionary.
     * Words added using this method will NOT be persisted.
     *
     * Params:
     *     word =      The word to be added.
     *     frequency = Corpus word frequency of this word. If omitted, a calculated value that ensures the word can be cut out will be used.
     *     tag =       Tag of the word.
     */
    void addWord(string word, int frequency = int.min, string tag = "") @safe {
        addWord(word.dtext, frequency, tag.dtext);
    }

    /**
     * Delete a single word from current dictionary.
     * Words deleted using this method will NOT be persisted.
     *
     * Params:
     *     word = The word to be deleted.
     */
    void delWord(string word) @safe {
        delWord(word.dtext);
    }

    /**
     * Segments an entire Chinese sentence into separated words.
     *
     * Params:
     *     sentence = The string to be segmented.
     *     cutAll =   Model type. True for full pattern, False for accurate pattern.
     *     useHmm =   Whether to use the Hidden Markov Model.
     *
     * Returns:
     *     An array containing all segments of the `sentence`.
     */
    dstring[] cut(dstring sentence, bool cutAll = false, bool useHmm = true) @safe {
        dstring[] cutImpl(dstring sentence, bool cutAll, bool useHmm) @safe {
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
                        foreach(dch; x) {
                            tokens.put(dch.dtext);
                        }
                    } else {
                        tokens.put(x);
                    }
                }
            }
        }

        return tokens.array;
    }

    /**
     * Extract all words from a Chinese sentence.
     * This method will extract as many words as possible, some of which may have overlapping parts.
     *
     * Params:
     *     sentence = The string to be segmented.
     *     useHmm =   Whether to use the Hidden Markov Model.
     *
     * Returns:
     *     An array containing all segments of the `sentence`.
     */
    dstring[] cutSearch(dstring sentence, bool useHmm = true) @safe {
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

    /**
     * Add a single word into current dictionary.
     * Words added using this method will NOT be persisted.
     *
     * Params:
     *     word =      The word to be added.
     *     frequency = Corpus word frequency of this word. If omitted, a calculated value that ensures the word can be cut out will be used.
     *     tag =       Tag of the word.
     */
    void addWord(dstring word, int frequency = int.min, dstring tag = "") @safe {
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

    /**
     * Delete a single word from current dictionary.
     * Words deleted using this method will NOT be persisted.
     *
     * Params:
     *     word = The word to be deleted.
     */
    void delWord(dstring word) @safe {
        addWord(word, 0);
    }

    /**
     * Load a user-defined dictionary alongside the main dictionary from the given path.
     *
     * Params:
     *     path = Path to the dictionary file.
     */
    void loadUserDict(string path) @safe {
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

    private:

    this(dstring dictContent) @safe {
        // this constructor is solely for unittest purpose
        loadImpl(dictContent);
        initialized = true;
    }

    void initialize() @safe {
        if (initialized) return; // fast lane before entering synchronized

        synchronized {
            if (initialized) return; // check again to prevent MT conflict
            
            load(dictionary); // no cache is used currently

            initialized = true;
        }
    }

    Pair!(int)[] calc(dstring sentence, int[][] dag) @safe {
        auto n = cast(int) sentence.length;
        auto logtotal = log(total);

        Pair!(int)[] route;
        route.length = n + 1;
        route[n] = Pair!int(0, 0.0);

        for (auto i = n - 1; i > -1; i--) {
            auto candidate = Pair!int(-1, -double.max);
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

    int[][] getDag(dstring sentence) @safe { // python impl = get_DAG
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

    dstring[] cutImplAll(dstring sentence) @safe { // python impl = __cut_all
        auto dag = getDag(sentence);

        auto lastpos = -1;
        auto tokens = appender!(dstring[]);
        auto engscan = false;
        auto engbuf = appender!(dchar[]);

        foreach(kk, v; dag) { // int to force size_t -> int conversion
            auto k = cast(long) kk;

            if (engscan && sentence[k .. k + 1].matchFirst(REGEX_ENGLISH).empty) {
                engscan = false;
                tokens.put(engbuf.array.dtext);
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
            tokens.put(engbuf.array.dtext);
        }

        return tokens.array;
    }

    dstring[] cutImplDwoH(dstring sentence) @safe { // python impl = __cut_DAG_NO_HMM
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
                auto arr = buf.array.dtext;
                if (arr.length > 0) {
                    tokens.put(arr);
                    buf.clear();
                }

                tokens.put(word);
            }

            x = y;
        }

        auto arr = buf.array.dtext;
        if (arr.length > 0) {
            tokens.put(arr);
            buf.clear();
        }

        return tokens.array;
    }

    dstring[] cutImplDH(dstring sentence) @safe { // python impl = __cut_DAG
        void bufSeg(ref Appender!(dchar[]) buffer, ref Appender!(dstring[]) tokens) @safe {
            import jieba.finalseg : finalcut = cut;

            auto buf = buffer.array.dtext;

            if (buf.length <= 0) return;

            if (buf.length == 1) {
                tokens.put(buf);
            } else if (freq.get(buf, 0) == 0) {
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

    int suggestFreq(dstring segment) @safe {
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

    void load(string path) @safe {
        auto content = path.readText;
        content.validate;

        loadImpl(content.dtext);
    }

    void loadImpl(dstring content) @safe { // not MT safe/idempotent (total)
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

    struct Pair(T) {
        T key;
        double freq;
    }
}

private:

enum REGEX_USERDICT = regex(`^(.+?)(?:\s+([0-9]+))?(?:\s+([a-z]+))?$`d, "m"); // modified regex to parse lines better
enum REGEX_ENGLISH = regex(`[a-zA-Z0-9]`d);
enum REGEX_HANIDEFAULT = regex(`([\u4E00-\u9FD5a-zA-Z0-9+#&\._%\-]+)`d);
enum REGEX_SKIPDEFAULT = regex(`(\r\n|\s)`d);

unittest {
    StdTestBuilder!("cut", "cutOutput");
	StdTestBuilder!("cutSearch", "cutSearchOutput");
    StdTestBuilder!("cutImplAll", "cutImplAllOutput");
	StdTestBuilder!("cutImplDwoH", "cutImplDwoHOutput");
    // StdTestBuilder!("cutImplDH", "cutImplDHOutput"); // already covered by cut - cutOutput
}

unittest {
	import std.stdio;

	auto x = new StandardSegmenter(UNITTEST_DICT);
	auto input = "测试用例里难以发现的隐藏问题"d;

	auto out1 = x.cutSearch(input).PrintSeg;
	auto case1 = "测试/试用/测试用例/里/难以/发现/的/隐藏/问题/";
	assert(out1 == case1, "Dict. modif. case 1 failed");

	x.addWord("用例");
	x.addWord("隐藏问题");
	auto out2 = x.cutSearch(input).PrintSeg;
	auto case2 = "测试/试用/用例/测试用例/里/难以/发现/的/隐藏/问题/隐藏问题/";
	assert(out2 == case2, "Dict. modif. case 2 failed");

	x.delWord("测试");
	x.delWord("用例");
	x.delWord("隐藏问题");
	auto out3 = x.cutSearch(input).PrintSeg;
	auto case3 = "试用/测试用例/里/难以/发现/的/隐藏/问题/";
	assert(out3 == case3, "Dict. modif. case 3 failed");

	x.delWord("测试用例");
	x.delWord("隐藏");
	auto out4 = x.cutSearch(input).PrintSeg;
	auto case4 = "测/试用/例里/难以/发现/的/隐藏/问题/";
	assert(out4 == case4, "Dict. modif. case 4 failed");

    x.addWord("测试用例");
	auto out5 = x.cutSearch(input).PrintSeg;
	auto case5 = "试用/测试用例/里/难以/发现/的/隐藏/问题/";
	assert(out5 == case5, "Dict. modif. case 5 failed");
}

version(unittest):

import std.traits : isSomeString;

template StdTestBuilder(string method, string output) {
	void testBody() {
		import std.stdio;

		import jieba.resources.testcases;

		auto x = new StandardSegmenter(UNITTEST_DICT);
		auto cnt = 0;

		for(int i = 0; i < testInput.length; i++) {
			mixin(`auto result = x.`, method, `(testInput[i].dtext).PrintSeg;`);
			if(mixin(output, `[i] != result`))
			{
				writeln("Actual: " ~ result);
				writeln("Expect: " ~ mixin(output, `[i]`));
				writeln("------");
				cnt++;
			}
		}

		assert(cnt == 0, "Some test cases failed for " ~ method);
	}

	alias StdTestBuilder = testBody;
}

string PrintSeg(dstring[] v) {
	import std.array;

	auto ret = appender!string;
	foreach(vv; v) {
		ret.put(vv.text);
        ret.put("/");
    }

	return ret.array;
}