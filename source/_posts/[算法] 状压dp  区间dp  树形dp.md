---
title: 算法 状压dp | 区间dp | 树形dp
date: 2025-4-3 10:55:00
tags: [算法, 动态规划]
---

## 状压dp

棋盘型状压,  重点考虑行与行之间的转移.

- 首先枚举每行可能的状态, **预处理出合法行状态**. 
- 可以选择预处理出行与行之间的合法转移

- `f[i][j]`代表处理完前i行, 第i行状态为j的xxx.
- 转移方程通过枚举前状态k来实现, 看k是否可以合法转移为j

> 玉米田 : 十字型 + 地图机制

```cpp
#include<iostream>
#include<vector>
#define rep(i, a, b) for(int i = (a); i <= (b); i ++ )
#define int long long
using namespace std;
const int N = 13, mod = 1e8;
int n, m;
vector<int> state; // 记录初始每行合法状态!
int g[N]; // 记录原图每行的状态
vector<int> trans[1 << N];
int f[N][1 << N];

bool check(int i)
{
    bool flag = false;
    while(i)
    {
        if(i & 1)
        {
            if(flag) return false;
            else flag = true;
        }
        else flag = false;
        i >>= 1;
    }
    return true;
}

signed main()
{
    cin >> n >> m;
    rep(i, 1, n)
    {
        int x = 0;
        rep(j, 0, m - 1) 
        {
            int y; cin >> y;
            x += !y << j;
        }
        g[i] = x;
    }
    
    for(int i = 0; i < 1 << m; i ++ )
        if(check(i)) state.push_back(i);
        
    for(auto a : state)
        for(auto b : state)
            if((a & b) == 0) trans[a].push_back(b);
    
    f[0][0] = 1;
    for(int i = 1; i <= n + 1; i ++ )
        for(auto a : state)
            for(auto b : trans[a])
                if((a & g[i]) == 0) // 要求不能种在不育土壤上
                    f[i][a] = (f[i][a] + f[i - 1][b]) % mod;
                    
    cout << f[n + 1][0] % mod << endl;
    return 0;
}
```

## 区间dp

### 环状区间dp

破环成链 + 区间dp

```cpp
#include<iostream>
#include<cstring>
#define rep(i, a, b) for(int i = (a); i <= (b); i ++ )
using namespace std;
const int N = 410;
int n; 
int a[N];
int f1[N][N], f2[N][N]; // 最小, 最大

signed main()
{
    cin >> n;
    rep(i, 1, n) cin >> a[i];
    rep(i, n + 1, 2 * n) a[i] = a[i - n];
    rep(i, 1, 2 * n) a[i] += a[i - 1];
    
    memset(f1, 0x3f, sizeof f1);
    rep(i, 1, 2 * n) f1[i][i] = 0;
    
    for(int len = 2; len <= n; len ++ )
        for(int l = 1; l + len - 1 <= 2 * n; l ++ )
        {
            int r = l + len - 1;
            for(int k = l; k < r; k ++ )
            {
                f1[l][r] = min(f1[l][r], f1[l][k] + f1[k + 1][r] + a[r] - a[l - 1]);
                f2[l][r] = max(f2[l][r], f2[l][k] + f2[k + 1][r] + a[r] - a[l - 1]);
            }
        }
    
    int mi = 0x3f3f3f3f;
    rep(i, 1, n + 1) mi = min(mi, f1[i][i + n - 1]);
    int ma = 0;
    rep(i, 1, n + 1) ma = max(ma, f2[i][i + n - 1]);
    cout << mi << endl;
    cout << ma << endl;
    return 0;
}
```

### 有关二叉树的区间dp

> 加分二叉树 : 给出中序遍历,  求出加分最高的二叉树并给出最高分和其前序遍历. 加分规则 : 根 + 左子树 * 右子树.

```cpp 
#include<iostream>
#define rep(i, a, b) for(int i = (a); i <= (b); i ++ )
#define int long long
using namespace std;
const int N = 35;
int n; 
int ord[N];
int f[N][N];
int root[N][N];

void dfs(int l, int r)
{
    if(l > r) return;
    cout << root[l][r] << " ";
    dfs(l, root[l][r] - 1);
    dfs(root[l][r] + 1, r);
}

signed main()
{
     cin >> n;
     rep(i, 1, n) cin >> ord[i];
     
     for(int len = 1; len <= n; len ++ )
        for(int l = 1; l + len - 1 <= n; l ++ )
        {
            int r = l + len - 1;
            if(len == 1) f[l][r] = ord[l], root[l][r] = l;
            else 
            {
                int sum;
                // 枚举根节点
                for(int k = l; k <= r; k ++ )
                {
                    sum = ord[k];
                    int left = k == l ? 1 : f[l][k - 1];
                    int right = k == r ? 1 : f[k + 1][r];
                    sum += left * right;
                    if(sum > f[l][r])
                    {
                        f[l][r] = sum;
                        root[l][r] = k;
                    }
                }
            }
        }
    cout << f[1][n] << endl;
    dfs(1, n);
    
    return 0;
}
```

### 二维区间dp

dfs + 区间dp

> 棋盘划分 

```cpp
#include<iostream>
#include<cstring>
#include<cmath>
#define rep(i, a, b) for(int i = (a); i <= (b); i ++ )
using namespace std;
const int M = 9;
int n;
int s[M][M];
double f[M][M][M][M][15]; // x1, y1, x2, y2, 还有k块
double X;

double get(int x1, int y1, int x2, int y2)
{
    double sum = s[x2][y2] - s[x1 - 1][y2] - s[x2][y1 - 1] + s[x1 - 1][y1 - 1] - X;
    return (double)sum * sum / n;
}


double dfs(int x1, int y1, int x2, int y2, int k)
{
    double& v = f[x1][y1][x2][y2][k];
    if(v >= 0) return v;
    if(k == 1) return v = get(x1, y1, x2, y2);
    
    v = 0x3f3f3f3f;
    // 横切
    for(int i = x1; i < x2; i ++ )
    {
        v = min(v, dfs(x1, y1, i, y2, k - 1) + get(i + 1, y1, x2, y2));
        v = min(v, dfs(i + 1, y1, x2, y2, k - 1) + get(x1, y1, i, y2));
    }
    // 纵切
    for(int i = y1; i < y2; i ++ )
    {
        v = min(v, dfs(x1, y1, x2, i, k - 1) + get(x1, i + 1, x2, y2));
        v = min(v, dfs(x1, i + 1, x2, y2, k - 1) + get(x1, y1, x2, i));
    }
    return v;
}

signed main()
{
    cin >> n;
    rep(i, 1, 8) rep(j, 1, 8)
    {
        cin >> s[i][j];
        s[i][j] += s[i - 1][j] + s[i][j - 1] - s[i - 1][j - 1];
    }
    
    memset(f, -1, sizeof f);
    
    X = (double)s[8][8] / n;
    
    printf("%.3lf", sqrt(dfs(1, 1, 8, 8, n)));
    return 0;
}
```

## 树形dp

### 树的直径

> 树的中心 : 求中心到其他所有点的最远距离, 中心是到所有点最远距离最小的点.

```cpp
#include<iostream>
#include<cstring>
#define rep(i, a, b) for(int i = (a); i <= (b); i ++ )
#define int long long
using namespace std;
const int N = 100010, M = N * 3;
int h[N], e[M], ne[M], idx;
int w[M];
int n;
int d1[N], d2[N];
int p[N];  // 记录当前子树的最长路径从哪个点来
int up[N];

void add(int a, int b, int c)
{
    e[idx] = b, w[idx] = c, ne[idx] = h[a], h[a] = idx++;
}

int dfs_d(int u, int fa)
{
    for(int i = h[u]; i != -1; i = ne[i])
    {
        int j = e[i];
        if(j == fa) continue;
        int ret = dfs_d(j, u) + w[i];
        if(ret > d1[u]) d2[u] = d1[u], d1[u] = ret, p[u] = j;
        else if(ret > d2[u]) d2[u] = ret;
    }
    return d1[u];
}

void dfs_up(int u, int fa)
{
    for(int i = h[u]; i != -1; i = ne[i])
    {
        int j = e[i];
        if(j == fa) continue;
        // 先处理up
        if(p[u] == j) up[j] = max(up[u], d2[u]) + w[i];
        else up[j] = max(up[u], d1[u]) + w[i];
        dfs_up(j, u);
    }
}

signed main()
{
    memset(h, -1, sizeof h);
    cin >> n;
    rep(i, 1, n - 1)
    {
        int a, b, c;
        cin >> a >> b >> c;
        add(a, b, c), add(b, a, c);
    }
    
    dfs_d(1, -1);
    dfs_up(1, -1);
    
    int ans = 0x3f3f3f3f;
    rep(i, 1, n) ans = min(ans, max(d1[i], up[i]));
    cout << ans << endl;
    return 0;
}
```

### 树形dp + 分组背包

> 二叉苹果树 : 给定一棵含有 n 个结点的树，树根编号为 1，且树上的每条边有一个边权 wedge j, 要求我们只保留树中的 m 条边，使得 树根 所在的 连通块 的所有边 边权之和 最大.

```cpp
// dfs + 分组背包
#include<iostream>
#include<cstring>
#define rep(i, a, b) for(int i = (a); i <= (b); i ++ )
#define int long long 
using namespace std;
const int N = 110;
int n, m;
int h[N], e[N * 2], ne[N * 2], w[N * 2], idx;
int f[N][N]; // 根节点为i, 要保留j根树枝的max

void add(int a, int b, int c)
{
    e[idx] = b, w[idx] = c, ne[idx] = h[a], h[a] = idx++;
}

void dfs(int u, int fa)
{
    for(int i = h[u]; i != -1; i = ne[i])
    {
        int x = e[i];
        if(x == fa) continue;
        dfs(x, u);
        // 每个子树就是一组, 选择保留当前子树中多少个树枝就是分组
        // u->j也需要一条树枝 
        for(int j = m; j >= 0; j -- )
            for(int k = 0; k < j; k ++ )
                f[u][j] = max(f[u][j], f[u][j - k - 1] + f[x][k] + w[i]);
    }
}

signed main()
{
    memset(h, -1, sizeof h);
    cin >> n >> m;
    rep(i, 1, n - 1)
    {
        int a, b, c;
        cin >> a >> b >> c;
        add(a, b, c), add(b, a, c);
    }
    
    dfs(1, -1);
    
    cout << f[1][m] << endl;
    return 0;
}
```

### 树形dp + 状态机

重点在于列举出状态, 以及状态之间的转移.

> 战略游戏 : 给出一个树, 一个人可以观察到所在点所连的所有边, 求观察到所有边的最小人数.

```cpp
#include<iostream>
#include<cstring>
#define rep(i, a, b) for(int i = (a); i <= (b); i ++ )
using namespace std;
const int N = 1510;
int n, m;
int h[N], e[N * 2], ne[N * 2], idx;
int f[N][2]; // 根节点为i, 此处不放/放士兵 士兵数的最小值
// 必须要接触所有的边
// f[i][0] += f[j][1] 必须放置
// f[i][1] += min(f[j][0], f[j][1])所有都是可放可不放

void add(int a, int b)
{
    e[idx] = b, ne[idx] = h[a], h[a] = idx++;
}

int dfs(int u, int fa)
{
    f[u][0] = 0, f[u][1] = 1;
    for(int i = h[u]; i != -1; i = ne[i])
    {
        int j = e[i];
        if(j == fa) continue;
        dfs(j, u);
        f[u][0] += f[j][1];
        f[u][1] += min(f[j][0], f[j][1]);
    }
}


signed main()
{
    while(cin >> n)
    {
        memset(h, -1, sizeof h);
        idx = 0;
        memset(f, 0x3f, sizeof f);
        rep(i, 1, n)
        {
            int u; cin >> u;
            char ch; cin >> ch >> ch;
            int k; cin >> k >> ch;
            while(k -- )
            {
                int v; cin >> v;
                add(u, v), add(v, u);
            }
        }
        
        dfs(1, -1);
        cout << min(f[1][0], f[1][1]) << endl; 
    }
    return 0;
}
```

> 皇宫看守 : 给出一个树, 一个人可以观察到当前点和所有邻点, 花销为当前点对应花销, 求观察到所有点的最小花销.

```cpp
#include<iostream>
#include<cstring>
#include<vector>
#define rep(i, a, b) for(int i = (a); i <= (b); i ++ )
using namespace std;
const int N = 1510;
int n;
int h[N], e[N * 2], ne[N * 2], idx;
int p[N]; // 记录安排侍卫的花销
int f[N][3];  // 根节点为i, 不放但父节点放/不放但子节点放/放
// f[i][0] += min(f[j][1], f[j][2]) -> 子节点可以放或子节点的子节点放
// f[i][1] += min(f[j][2] + 集合min(f[k][2], f[k][1]))  -> 子节点有一个放, 其他可放可不放
// f[i][2] += min(f[j][1], f[j][2], f[j][0]);
bool st[N];


void add(int a, int b)
{
    e[idx] = b, ne[idx] = h[a], h[a] = idx++;
}

void dfs(int u)
{
    f[u][2] = p[u];
    for(int i = h[u]; i != -1; i = ne[i])
    {
        int j = e[i];
        dfs(j);
        f[u][0] += min(f[j][1], f[j][2]);
        f[u][2] += min(f[j][1], min(f[j][2], f[j][0]));
    }
    
    // 分别每个子节点为必2点
    f[u][1] = 0x3f3f3f3f;
    for(int i = h[u]; i != -1; i = ne[i])
    {
        int j = e[i];
        f[u][1] = min(f[u][1], f[u][0] - min(f[j][1], f[j][2]) + f[j][2]);
    }
}

signed main()
{
    memset(h, -1, sizeof h);
    cin >> n;
    int t = n;
    while(t -- )
    {
        int i, k;
        cin >> i >> p[i] >> k;
        while(k -- )
        {
            int r; cin >> r;
            add(i, r);
            st[r] = true;
        }
    }
    
    int root = 1;
    while(st[root]) root++;
    
    dfs(root);
    cout << min(f[root][1], f[root][2]) << endl;
    return 0;
}
```

