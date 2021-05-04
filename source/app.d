import std.json;
import std.stdio;
import core.stdc.stdlib;

import jieba.resources;
import jieba.stdseg;
import jieba.finalseg;
import jieba.posseg.viterbi;

import std.conv;
void main()
{
	// todo: tokenizer, posseg, tfidf
	
	auto w = 0.0;
	auto x = viterbi("这是一句测试用的句子"d, w);

	writeln;

	// system("pause");
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