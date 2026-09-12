# Git 常用命令小抄

这份文档是给当前项目 `anime_chat_app` 用的本地 Git 入门指南。目标不是一次学完 Git，而是让你在日常开发里能做到三件事：

- 能保存一个稳定版本。
- 改乱了能判断当前发生了什么。
- 想尝试不同方案时，可以用分支互不覆盖。

## 先理解三个核心概念

### 工作区

工作区就是你正在编辑的项目文件夹。

比如你改了 `lib/chat_page.dart`，但还没有执行 `git add`，这个修改就在工作区里。

### 暂存区

暂存区可以理解成“这次准备提交的文件清单”。

执行：

```powershell
git add .
```

就是把当前改动放进暂存区，告诉 Git：“这些内容我要放进下一次版本存档里。”

### 提交

提交，也就是 `commit`，可以理解成一次正式存档。

执行：

```powershell
git commit -m "save 20"
```

会在本地生成一个版本点。以后你可以查看它、切回它、基于它开分支。

## 本项目当前推荐工作流

日常最常用的是这一套：

```powershell
git status
git add .
git commit -m "save 20"
git push
```

含义是：

- `git status`：先看现在有哪些改动。
- `git add .`：把所有改动加入暂存区。
- `git commit -m "save 20"`：本地保存一个版本。
- `git push`：上传到 GitHub。

新手口诀：

```text
先 status，看清楚；再 add，准备好；commit 是本地存档；push 是上传云端。
```

## 查看当前状态：git status

命令：

```powershell
git status
```

作用：

查看当前分支、有没有未提交修改、有没有文件已暂存、是否领先或落后 GitHub。

常见输出 1：工作区干净

```text
On branch main
Your branch is up to date with 'origin/main'.

nothing to commit, working tree clean
```

意思是：

- 你在 `main` 分支。
- 本地和 GitHub 一样新。
- 没有未提交修改。

常见输出 2：有修改但还没暂存

```text
On branch main
Changes not staged for commit:
  modified:   lib/chat_page.dart
```

意思是：

- 你改了 `lib/chat_page.dart`。
- 这个改动还没有进入下一次提交清单。

下一步通常是：

```powershell
git add lib/chat_page.dart
```

或者把所有改动都加进去：

```powershell
git add .
```

常见输出 3：有文件已暂存，等待提交

```text
On branch main
Changes to be committed:
  new file:   docs/git_common_commands.md
  modified:   lib/chat_page.dart
```

意思是：

- 这些文件已经进入暂存区。
- 执行 `git commit` 后，它们会被保存成一个版本。

常见输出 4：本地领先 GitHub

```text
On branch main
Your branch is ahead of 'origin/main' by 1 commit.
```

意思是：

- 你本地已经 commit 了 1 次。
- 但这 1 次还没有上传到 GitHub。

下一步通常是：

```powershell
git push
```

## 简洁状态：git status --short --branch

命令：

```powershell
git status --short --branch
```

作用：

用很短的格式查看状态，适合快速判断。

典型输出：

```text
## main...origin/main [ahead 1]
 M lib/chat_page.dart
A  docs/git_common_commands.md
?? temp.txt
```

怎么看：

- `## main...origin/main [ahead 1]`：本地 `main` 比 GitHub 多 1 个提交。
- ` M 文件名`：文件被修改了，但还没有暂存。
- `M  文件名`：文件被修改了，并且已经暂存。
- `A  文件名`：新增文件已经暂存。
- `?? 文件名`：新文件还没有被 Git 管理。

## 把改动加入暂存区：git add

加入全部改动：

```powershell
git add .
```

只加入某个文件：

```powershell
git add lib/chat_page.dart
```

作用：

告诉 Git：“这些改动我要放进下一次 commit。”

常见 warning：

```text
warning: in the working copy of 'xxx.dart', LF will be replaced by CRLF the next time Git touches it
```

意思是：

- 这是换行符提醒，不是报错。
- `LF` 是 Linux/macOS 常见换行。
- `CRLF` 是 Windows 常见换行。
- 一般不影响代码运行。

看到这个 warning 后，通常可以继续：

```powershell
git commit -m "save 20"
```

## 本地保存版本：git commit

命令：

```powershell
git commit -m "save 20"
```

作用：

把暂存区里的改动保存成一个本地版本点。

典型输出：

```text
[main abc1234] save 20
 3 files changed, 120 insertions(+), 8 deletions(-)
 create mode 100644 docs/git_common_commands.md
```

怎么看：

- `main`：提交发生在哪个分支。
- `abc1234`：这次提交的短编号。
- `save 20`：提交名称。
- `3 files changed`：这次改了 3 个文件。
- `insertions`：新增行数。
- `deletions`：删除行数。
- `create mode`：新增了文件。

## 修改最近一次提交名称：git commit --amend

如果刚刚 commit 后发现名字写错了，可以改最近一次提交名称。

命令：

```powershell
git commit --amend -m "新的提交名称"
```

适合场景：

- 刚提交完。
- 发现提交名称不清楚。
- 想把 `save 20` 改成更具体的描述。

如果还没有 `git push`，这样改通常很安全。

如果已经 push 到 GitHub，再 amend 就需要：

```powershell
git push --force-with-lease
```

新手建议：

- 没 push：可以放心改。
- 已 push：除非你很确定，否则先不要强推。

## 上传到 GitHub：git push

命令：

```powershell
git push
```

作用：

把本地 commit 上传到 GitHub。

典型输出：

```text
Enumerating objects: 12, done.
Counting objects: 100% (12/12), done.
Writing objects: 100% (8/8), 2.30 KiB | 2.30 MiB/s, done.
To github.com:Star-Aria/anime_chat.git
   abc1234..def5678  main -> main
```

怎么看：

- `Writing objects`：正在上传内容。
- `main -> main`：本地 `main` 上传到了 GitHub 的 `main`。
- 没有 error 就通常代表成功。

如果 `git status` 里看到：

```text
Your branch is ahead of 'origin/main' by 1 commit.
```

说明你本地有提交还没上传。执行 `git push` 即可。

## 从 GitHub 拉取更新：git pull

命令：

```powershell
git pull
```

作用：

把 GitHub 上的新提交下载到本地，并合并进当前分支。

适合场景：

- 你在另一台电脑上改过代码。
- 你和别人一起开发。
- GitHub 上比本地更新。

典型输出：

```text
Updating abc1234..def5678
Fast-forward
 lib/chat_page.dart | 20 +++++++++++++-------
```

意思是：

- 本地成功更新到了 GitHub 的新版本。
- `Fast-forward` 是一种最简单的合并方式，通常不用担心。

新手建议：

在开始一天的开发前，可以先：

```powershell
git pull
```

## 查看提交历史：git log

命令：

```powershell
git log --oneline --decorate --graph -n 20
```

作用：

查看最近 20 个版本点。

典型输出：

```text
* 3fb9051 (HEAD -> main, origin/main) save 19
* b46707f save 18
* 3350c85 save 17
```

怎么看：

- 每一行是一个 commit。
- `3fb9051` 是版本编号。
- `HEAD -> main` 表示你当前正在这个版本上。
- `origin/main` 表示 GitHub 的 `main` 也在这个版本上。

如果你想回到某个旧版本，通常先从这里复制版本编号。

## 查看具体改了什么：git diff

查看还没暂存的改动：

```powershell
git diff
```

查看已经暂存、准备 commit 的改动：

```powershell
git diff --staged
```

典型输出：

```diff
- old line
+ new line
```

怎么看：

- `-` 开头是删除的内容。
- `+` 开头是新增的内容。

如果输出很多，按 `q` 可以退出。

## 撤销还没暂存的修改：git restore

命令：

```powershell
git restore lib/chat_page.dart
```

作用：

把某个文件恢复到最近一次 commit 的状态。

重要提醒：

这个命令会丢掉该文件当前未提交的修改。执行前一定先确认：

```powershell
git status
git diff lib/chat_page.dart
```

如果你只是想看看，不确定要不要丢，先不要执行 `restore`。

## 取消暂存：git restore --staged

命令：

```powershell
git restore --staged lib/chat_page.dart
```

作用：

把文件从暂存区拿出来，但保留文件内容的修改。

适合场景：

你执行了：

```powershell
git add .
```

后来发现某个文件暂时不想放进这次提交。

执行 `restore --staged` 后，文件内容不会丢，只是不再进入本次 commit。

## 开新分支尝试方案：git switch -c

命令：

```powershell
git switch -c try-new-search-logic
```

作用：

从当前版本开一条新路线。

适合场景：

- 想尝试一个不确定的方案。
- 想做实验，又不想影响 `main`。
- 想同时保留 A/B 两种解决方式。

典型输出：

```text
Switched to a new branch 'try-new-search-logic'
```

之后你在这个分支上的 commit 都属于这条路线。

## 切换分支：git switch

切回主分支：

```powershell
git switch main
```

切到实验分支：

```powershell
git switch try-new-search-logic
```

典型输出：

```text
Switched to branch 'main'
Your branch is up to date with 'origin/main'.
```

注意：

如果你有未提交修改，Git 可能不让你切分支，因为会覆盖文件。遇到这种情况，先 `git status` 看清楚。

## 查看分支：git branch

命令：

```powershell
git branch
```

典型输出：

```text
* main
  try-new-search-logic
```

怎么看：

- `*` 表示当前所在分支。
- 没有 `*` 的是其他分支。

查看本地和远程全部分支：

```powershell
git branch --all --verbose
```

## 合并分支：git merge

假设你在 `try-new-search-logic` 分支完成了实验，想合并回 `main`。

先切回 `main`：

```powershell
git switch main
```

再合并：

```powershell
git merge try-new-search-logic
```

典型成功输出：

```text
Updating abc1234..def5678
Fast-forward
 lib/web_context_service.dart | 50 +++++++++++++++++++++
```

意思是：

- 实验分支的改动已经进入 `main`。

如果出现 conflict，说明两个分支改到了同一块内容，需要手动解决冲突。新手阶段遇到 conflict 不要慌，先停下来执行：

```powershell
git status
```

看 Git 告诉你哪些文件冲突了。

## 临时保存现场：git stash

命令：

```powershell
git stash
```

作用：

把当前未提交修改临时收起来，让工作区变干净。

适合场景：

- 你正在改东西，但还不想 commit。
- 突然需要切换分支。
- Git 提示当前修改会妨碍切换。

查看 stash 列表：

```powershell
git stash list
```

恢复最近一次 stash：

```powershell
git stash pop
```

注意：

`stash pop` 会把修改拿回来，并从 stash 列表里删除。如果你想更保守，可以用：

```powershell
git stash apply
```

它会拿回修改，但保留 stash 记录。

## 查看远程仓库：git remote -v

命令：

```powershell
git remote -v
```

作用：

查看当前项目连接了哪些 GitHub 仓库。

本项目整理后的典型输出：

```text
origin  git@github.com:Star-Aria/anime_chat.git (fetch)
origin  git@github.com:Star-Aria/anime_chat.git (push)
```

怎么看：

- `origin` 是远程仓库的默认名字。
- `fetch` 表示从这个地址下载。
- `push` 表示上传到这个地址。

## 下载远程信息但不改代码：git fetch

命令：

```powershell
git fetch
```

作用：

只更新“GitHub 那边现在到哪了”的信息，不自动合并代码。

适合场景：

- 想看看 GitHub 有没有新提交。
- 不想让当前代码被自动合并影响。

常见搭配：

```powershell
git fetch
git status
```

如果看到：

```text
Your branch is behind 'origin/main' by 1 commit.
```

说明 GitHub 比你本地多 1 个提交，可以考虑：

```powershell
git pull
```

## 查看某个版本内容：git show

命令：

```powershell
git show 3fb9051
```

作用：

查看某一次 commit 的详细内容。

典型输出包括：

```text
commit 3fb9051...
Author: ...
Date: ...

    save 19

diff --git a/lib/chat_page.dart b/lib/chat_page.dart
```

怎么看：

- 上面是提交信息。
- 下面是这次提交具体改动。

如果输出很多，按 `q` 退出。

## 只查看旧版本，不真正回退：git switch --detach

命令：

```powershell
git switch --detach 3fb9051
```

作用：

临时切到某个旧版本看看。

适合场景：

- 想确认以前某个版本能不能跑。
- 想对比旧代码。
- 不想真的把当前分支回退。

回到主分支：

```powershell
git switch main
```

注意：

`detached HEAD` 状态像是“站在历史版本上参观”。新手阶段不要在这个状态下长期开发。

## 回退方式怎么选

### 只是不想要某个文件的当前修改

用：

```powershell
git restore 文件名
```

### 只是想看看旧版本

用：

```powershell
git switch --detach 版本号
```

看完后：

```powershell
git switch main
```

### 已经 commit 了，但想新增一个“撤销提交”

用：

```powershell
git revert 版本号
```

它会新增一个 commit，用来抵消旧 commit 的改动。

新手阶段更推荐 `revert`，因为它不会删除历史。

### 不建议新手随便用

```powershell
git reset --hard
```

这个命令会强行把项目恢复到某个版本，并丢弃工作区修改。除非你非常确定，否则先不要用。

## Git 和 GitHub 的区别

Git 是本地版本管理工具。

它负责：

- 本地保存版本。
- 查看历史。
- 创建分支。
- 回到旧版本。
- 比较改动。

GitHub 是云端代码仓库平台。

它负责：

- 备份代码。
- 多台电脑同步。
- 和别人协作。
- 在线查看代码历史。

可以这样记：

```text
git commit = 存到自己电脑
git push   = 上传到 GitHub
git pull   = 从 GitHub 下载更新
```

## 新手安全建议

每次开始改代码前：

```powershell
git status
```

每次完成一个小目标后：

```powershell
git add .
git commit -m "简短说明这次改了什么"
```

每次想试一个不确定方案：

```powershell
git switch -c try-something
```

每次看到 Git 输出看不懂：

```powershell
git status
```

先读状态，再决定下一步。

最重要的一句：

```text
能跑就 commit，想试就 branch，改乱先 status。
```
