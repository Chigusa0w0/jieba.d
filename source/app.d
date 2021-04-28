import std.json;
import std.stdio;
import core.stdc.stdlib;

import jieba.resources;
import jieba.stdseg;
import jieba.finalseg;

import std.conv;
void main()
{
	// todo: tokenizer, posseg
	
	auto x = new StandardSegmenter(`.\dict\dict.txt`);

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