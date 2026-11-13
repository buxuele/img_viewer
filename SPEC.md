# img_viewer spec

Every requirement is a row with an id. Agents build against approved rows; commits cite the ids they serve. `pullboard spec check` lints this file.

Statuses: approved = decided · draft = proposed · pending = open question · fact = true today · wont = won't build, decided and kept · retired = no longer applies, kept. Ids are permanent: never delete or renumber a row. Tiers: must · aim.

Write each requirement as one row under its section, in this format. The fence keeps the example out of the spec, so no placeholder id is ever committed; your own rows go below, outside it.

```text
- G1 [draft, must] The first thing the client needs, in one line. | gate: the test that proves it
- K1 [draft, must] A constraint, e.g. runs locally with no account. | gate: review
```

## G · Goals: what the client asked for
- G1 [draft, must] 复刻 Windows 照片查看器的单张看图体验：窗口外观、底部工具栏、左右切换、缩放平移、旋转、删除、幻灯片与右键菜单。 | gate: tests 与 效果图
- G2 [draft, must] 打开本地文件夹后按自然顺序浏览其中图片，并记住最近打开的文件夹。 | gate: tests/test_library.py

## K · Constraints
- K1 [draft, must] 全本地运行，Python 3.14 加 FastAPI 加原生 HTML/CSS/JS，不联网、不登录、不收集数据。 | gate: review
- K2 [draft, must] 界面全中文、零 emoji、可见文字不小于 14px，配色为浅灰窗口加深色文字。 | gate: tests/test_ui_contract.py

## A · Web app

- A1 [draft, must] Every change ships with a test that fails without it. Why: a test that passes either way proves nothing. | gate: review
- A2 [draft, must] Main only moves when the whole test suite passes. Why: two changes can each pass alone and still break each other. | gate: review
- A3 [draft, must] Every page works at phone width before it ships. Why: a page that only works on a laptop is a bug nobody reports. | gate: review
- A4 [draft, must] Secrets never appear in code, logs or commits. Why: a key pushed once stays public, even after you delete it. | gate: review
- A5 [draft, must] A new dependency comes with a one-line reason. Why: every package you add is code you now maintain. | gate: review
- A6 [draft, must] An error a person sees says what to do next. Why: "something went wrong" is a support ticket waiting to happen. | gate: review
- A7 [draft, must] Tests bind a local port, so a sandboxed agent asks the person instead of rewriting the tests. Why: a test rewritten into a fake passes inside the sandbox and proves nothing about the real server. | gate: review
- A8 [pending, must] The app is built with: (choose one). Choices: Next.js, SvelteKit, Rails, Something else. | gate: review
- A9 [pending, must] It deploys to: Vercel. Choices: Vercel, Netlify, Fly.io, My own server. | gate: review
- A10 [pending, must] People sign in with: Email links. Choices: Email links, Passwords, Google, No sign-in yet. | gate: review
- A11 [pending, must] A change is done when: It runs on a preview link. Choices: It runs on a preview link, Its tests pass, I have looked at it. | gate: review
<!-- pullboard-blueprint-kind web-app product -->
<!-- pullboard-blueprint web-app 1 -->
- A12 [draft, must] 常见图片格式可浏览：jpg jpeg png gif bmp webp tif tiff heic heif avif。 | gate: tests/test_library.py
- A13 [draft, must] 主界面按 Windows 照片查看器还原：标题栏、图像区、左右大箭头、底部工具栏。 | gate: 效果图
- A14 [draft, must] 滚轮以光标位置为中心缩放，双击在适应窗口与 100% 之间切换，放大后可拖动平移。 | gate: tests/test_ui_contract.py
- A15 [draft, must] 键盘支持方向键、PageUp/PageDown、加号减号、Ctrl+R 旋转、F11 幻灯片、Esc 退出、Delete 删除。 | gate: tests/test_ui_contract.py
- A16 [draft, must] 旋转结果持久保存到应用数据库，不直接改写原文件。 | gate: tests/test_api.py
- A17 [draft, must] 右键菜单提供打开、复制、复制路径、在访达中显示、另存为、设为桌面背景、旋转、删除、属性、选项。 | gate: tests/test_api.py
- A18 [draft, must] 选项可设置打开时适应窗口、始终显示菜单、记住最近项目、滚轮缩放、双击切换、背景色、幻灯片间隔与主题。 | gate: tests/test_api.py
- A19 [draft, must] 幻灯片全屏播放，支持间隔、循环、随机与三种背景主题。 | gate: tests/test_ui_contract.py
- A20 [draft, must] 删除先二次确认，再把文件移入废纸篓而不是永久删除。 | gate: tests/test_api.py
- A21 [draft, must] 文件夹网格超过 30 张时分页，显示页码与总数。 | gate: tests/test_ui_contract.py
- A22 [draft, must] 大图先显示预览再换原图，预览缓存按路径与修改时间失效。 | gate: tests/test_api.py
