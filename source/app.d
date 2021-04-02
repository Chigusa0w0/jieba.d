import std.json;
import std.stdio;
import core.stdc.stdlib;

import jieba.resources;
import jieba.stdseg;

void main()
{
	auto x = new StandardTokenizer(`.\dict\dict.txt`);
	x.addWord("测试用例");
	x.addWord("隐藏问题");
	auto v = x.cutSearch("测试用例里难以发现的隐藏问题");
	foreach(vv; v) {
		write(vv ~ "/");
    }
	writeln;

	system("pause");
}
