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
