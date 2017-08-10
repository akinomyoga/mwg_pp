# ev3v2

**これは何?** GNU awk 上で動く言語処理系の試験実装。

**実装** 本体は ev3v2.awk。ev3v2.awk は本来 master ブランチで生成される (複数のソースを連結)。

**言い訳** 技術的可能性を確認するための試験実装なので、実装していない機能やバグなどある。そもそも言語仕様を忘れた。

**経緯** 本当は自分用プリプロセッサ mwg_pp.awk の 1 コンポーネント mwg_pp.eval2 を置き換える為に試験的に作っていた mwg_pp.ev3 の major version 2 だった。遅すぎるので実用にならないと判断され放棄された。

## 例 demo-sierpinski.ev3

```js
#!/usr/bin/env ev3v2
// -*- mode:c++ -*-
arr = [1];
for (n = 0; n < 64; n++) {
  s = "";
  for (r = 0; r <= n; r++)
    s += arr[r] % 2 == 1? "*": " ";
  puts(s);
  for (r = n; r >= 0; r--)
    arr[r + 1] = arr[r + 1] + arr[r] & 1;
}
```

```sh
$ ./ev3v2.awk demo-sierpinski.ev3
*
**
* *
****
*   *
**  **
* * * *
********
*       *
**      **
* *     * *
****    ****
*   *   *   *
**  **  **  **
* * * * * * * *
****************
*               *
**              **
* *             * *
****            ****
*   *           *   *
**  **          **  **
* * * *         * * * *
********        ********
*       *       *       *
**      **      **      **
* *     * *     * *     * *
****    ****    ****    ****
*   *   *   *   *   *   *   *
**  **  **  **  **  **  **  **
* * * * * * * * * * * * * * * *
********************************

```

## 例 demo-maze.ev3

```js
#!/usr/bin/env ev3v2
// -*- mode:js -*-

srand();
for (i = 10 + rand() * 10 % 20 | 0; i--; ) rand();

NX = 10;
NY = 10;
kabe = [];
cell = [];
for (x = 0; x < NX; x++) cell[x] = [], kabe[x] = [];

check = (x, y) => if (0 <= x && x < NX && 0 <= y && y < NY && !cell[x][y]) {
  cell[x][y] = true;
  search(x, y);
  true
};
searches = [
  ((x, y) => if (check(x + 1, y)) kabe[x][y] |= 1),
  ((x, y) => if (check(x - 1, y)) kabe[x - 1][y] |= 1),
  ((x, y) => if (check(x, y - 1)) kabe[x][y - 1] |= 2),
  ((x, y) => if (check(x, y + 1)) kabe[x][y] |= 2)
];
search = (x, y) => {
  cell[x][y] = true;
  var buff = [0, 1, 2, 3];
  for (var c = 4; c >= 1; c--)
    searches[buff.splice(rand() * c, 1)[0]](x, y);
};

search(0, 0);

var result = "";
draw_xkabe = (y) => {
  result += "|  ";
  for (x = 0; x < NX - 1; x++)
    result += kabe[x][y] & 1? "   ": "|  ";
  result += "|\n";
};
draw_ykabe = (y) => {
  for (x = 0; x < NX; x++)
    result += kabe[x][y] & 2? "+  ": "+--";
  result += "+\n";
};

draw_ykabe(-1);
for (y = 0; y < NY; y++) {
  draw_xkabe(y);
  draw_ykabe(y);
};
puts(result);

//puts("[" + kabe.join() + "]");
check = null;
searches = null;
search = null;
draw_ykabe = draw_xkabe = null;

```

```sh
$ ./ev3v2.awk demo-maze.ev3
+--+--+--+--+--+--+--+--+--+--+
|     |        |              |
+--+  +  +--+  +  +  +--+--+  +
|  |  |  |     |  |     |  |  |
+  +  +  +  +--+  +--+  +  +  +
|  |     |  |     |  |  |     |
+  +--+--+  +  +--+  +  +--+  +
|     |     |     |  |     |  |
+  +--+  +--+--+  +  +--+  +  +
|        |     |  |     |  |  |
+  +--+--+  +  +  +  +--+  +  +
|  |        |  |     |     |  |
+  +--+--+  +  +--+--+  +--+  +
|           |        |  |     |
+--+--+--+--+--+--+  +  +--+--+
|              |     |        |
+  +--+  +  +--+  +--+  +--+  +
|  |  |  |  |     |     |     |
+  +  +  +--+  +--+--+--+  +  +
|     |                    |  |
+--+--+--+--+--+--+--+--+--+--+

```
