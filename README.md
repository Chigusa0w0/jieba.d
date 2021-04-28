Jieba.d
========
Jieba.d 是[结巴中文分词](https://github.com/fxsjy/jieba)的 D 语言实现版本

当前版本的 Jieba.d 基于结巴中文分词 0.42.1 版本实现。实现了除 Paddle 模式外的全部功能。

Jieba.d 的各接口与 Python 版本基本一致。

## 项目文档

请阅读本项目代码内嵌的 ddoc 文档

## 项目依赖

- D `>= 2.096.0`
- asdf `>= 0.7.5`

## 项目构建

- 如需编译示例程序
  - 推荐使用 `dub build` 快速构建

- 如与其他项目编译
  - 需设置编译器参数，为 `ImportExpression` 提供到 `source/resources` 目录的搜索路径
  - 在 DMD 下该参数形如 `-J="../source/resources"`，其他编译器下的参数请参照编译器手册

--------------------

Jieba.d
========
Jieba.d is the D implementation of the [Jieba Chinese Word Segmentation](https://github.com/fxsjy/jieba)

The current version of Jieba.d is based on version 0.42.1 of the Python Jieba. It implements all the features except the Paddle mode.

The interfaces of Jieba.d are principally the same as the Python version.

## Documentation

Please read the `ddoc` documentation embedded in the code.

## Dependencies

- D `>= 2.096.0`
- asdf `>= 0.7.5`

## How to build

- If you want to compile the sample program
  - Using `dub build` is recommended.

- If compiled with other projects
  - Please provide an `ImportExpression` search path to `source/resources` directory of this project in the compiler command line.
  - When using DMD, the parameter looks like `-J="../source/resources"`. If you are using other compilers, please refer to the compiler manual for the parameter format.
