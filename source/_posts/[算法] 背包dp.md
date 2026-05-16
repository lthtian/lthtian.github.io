---
title: 算法 背包dp
date: 2025-3-30 08:54:00
tags: [算法]
---

## 关于"不大于""恰好""至少是"的讨论

最标准的背包问题中, 装入背包的体积是要不大于m的, 但有些题目要求装入体积恰好是m, 或者至少是m, 思路一样, 但是初始化和最终获取答案的方式有区别.

```cpp
// 不大于
for(int i = 1; i <= n; i ++ )
    for(int j = m; j >= v[i]; j -- )
        f[j] = max(f[j], f[j - v[i]] + w[i]);
cout << f[m] << endl;
```

这是最普通的一维优化01背包, 针对不大于的情况, 我们保证的是j - v[i]一定大于等于0, 因为体积不可能不大于负数, 初始化都是0, 至于原因, 是因为"什么都不装"也是"不大于"中的一种合法条件, 什么都不装值一定是0, 也就是说没个状态一定都有值为0这个合法条件, 可以取得并使用.

```cpp
// 恰好
memset(f, -0x3f, sizeof f);
f[0] = 0;
for(int i = 1; i <= n; i ++ )
    for(int j = m; j >= v[i]; j -- )
        f[j] = max(f[j], f[j - v[i]] + w[i]);

int ans = 0;
for(int i = 1; i <= m; i ++ ) ans = max(ans, f[i]);
cout << ans << endl;
```

恰好相比于不大于, 对f全部进行了最小化, 只有f[0] = 0, 原因依旧从定义分析 : 初始化的 F 数组事实上就是在没有任何物品可以放入背包时的合法状态。如果要求背包恰好装满，那么此时只有容量为 0 的背包可以在什么也不装且价值为 0 的情况下被“恰好装满”，其它容量的背包均没有合法的解，属于未定义的状态，应该被赋值为 -∞ 了.

另外这种恰好得到结果不会涵盖前面的状态, 每个状态是相互独立的, 如果没有明确指明是恰好为多少, 通常要遍历统计一遍.

```cpp
memset(f, -0x3f, sizeof f);
f[0] = 0;
for(int i = 1; i <= n; i ++ )
    for(int j = m; j >= 0; j -- )
        f[j] = max(f[j], f[max(0, j - v[i])] + w[i]);
cout << f[m] << endl;
```

"至少是"相比于前两者, 多了j - v[i] < 0的情况, 因为"至少是负数"在理论上来说是正确的, 所以我们应当将小于0的情况也纳入考虑, 由于数组下标限制, 小于0的情况就当0处理.

## 背包问题求具体方案

求具体方案是一种提醒, 其解法在于通过背包dp得到的f数组倒推选择从而得到方案.

```cpp
#include<iostream>
#define rep(i, a, b) for(int i = (a); i <= (b); i ++ )
using namespace std;
const int N = 1010;
int n, m;
int w[N][N];
int f[N][N];
int ans[N];

signed main()
{
    cin >> n >> m;
    rep(i, 1, n) rep(j, 1, m) cin >> w[i][j];
    
    for(int i = 1; i <= n; i ++ )
        for(int j = 0; j <= m; j ++ )
        {
            f[i][j] = f[i - 1][j];
            for(int k = 1; k <= m; k ++ )
                if(j - k >= 0) f[i][j] = max(f[i][j], f[i - 1][j - k] + w[i][k]);
        }
    
    cout << f[n][m] << endl;
    
    int j = m;
    for(int i = n; i > 0; i -- )
    {
        for(int k = 1; k <= m; k ++ )
        {
            if(j - k >= 0 && f[i][j] == f[i - 1][j - k] + w[i][k])
            {
                ans[i] = k;
                j -= k;
                break;
            }
        }
    }
    
    for(int i = 1; i <= n; i ++ )
    {
        cout << i << " " << ans[i] << endl;
    }
    
    return 0;
}
```

这是一个分组背包的方案倒推, 可以掌握到关键在于找到`f[i][j] == f[i - 1][j - k] + w[i][k]`, 这说明在最后的方案选择一定选择了第i件, 然后`j -= k;`就是原来怎么加的, 现在怎么减回去, 就这样一直到这推就可以得到方案.

## 背包问题求最优方案数

关键在于维护另外一个dp, 用来记录体积为j时的方案数.

```cpp
// 从方案数变成最优方案数, 需要再用一个dp维护使用前i个物品的最优方案数
#include<iostream>
#include<algorithm>
#include<cstring>
#define rep(i, a, b) for(int i = (a); i <= (b); i ++ )
#define int long long
using namespace std;
const int N = 1010, mod = 1e9 + 7;
int n, m;
int v[N], w[N];
int f[N], g[N];

signed main()
{
    cin >> n >> m;
    rep(i, 1, n) cin >> v[i] >> w[i];
    
    
    memset(f, -0x3f, sizeof f);
    f[0] = 0;
    g[0] = 1;
    
    for(int i = 1; i <= n; i ++ )
        for(int j = m; j >= v[i]; j -- )
        {
            int ma = max(f[j], f[j - v[i]] + w[i]);
            int cnt = 0;
            if(ma == f[j]) cnt = g[j];
            if(ma == f[j - v[i]] + w[i]) cnt += g[j - v[i]];
            g[j] = cnt % mod;
            f[j] = ma;
        }
    
    int ans = 0;
    rep(i, 0, m) ans = max(ans, f[i]);
    int cnt = 0;
    rep(i, 0, m) 
        if(ans == f[i])
            cnt += g[i];
    cout << cnt % mod << endl;
    
    return 0;
}
```

我们可以看到g[i]是根据f[j]的两个源状态所对应的结果所改变的, 思路很简单, 就是谁大就记录谁的方案数, 一样大就一起记录.

## 混合背包

不同物品对应不同的处理方法, 其实就是分别对待就行, 可以把01背包当成特殊的多重背包处理, 这样就只用处理完全背包和多重背包了, 更具n大小判断多重背包用哪个版本的.

```cpp
#include<iostream>
#define rep(i, a, b) for(int i = (a); i <= (b); i ++ )
#define int long long 
using namespace std;
const int N = 1010, W = 6010;
int n, m;
int v[N], s[N], w[N];
int f[W];

signed main()
{
    cin >> n >> m;
    int op;
    rep(i, 1, n) 
    {
        cin >> v[i] >> w[i] >> op;
        if(op == -1) s[i] = 1;
        else if(op == 0) s[i] = 1010;
        else s[i] = op;
    }
    
    for(int i = 1; i <= n; i ++ )
    {
        if(s[i] == 0) // 完全背包
            for(int j = v[i]; j <= m; j ++ ) f[j] = max(f[j], f[j - v[i]] + w[i]);
        else  // 多重背包
        {
            for(int k = 1; k <= s[i]; k *= 2)
            {
                for(int j = m; j >= k * v[i]; j -- )
                    f[j] = max(f[j], f[j - k * v[i]] + k * w[i]);
                s[i] -= k;
            }
            if(s[i])
            {
                for(int j = m; j >= s[i] * v[i]; j --)
                    f[j] = max(f[j], f[j - s[i] * v[i]] + s[i] * w[i]);
            }
        }
    }
        
    cout << f[m] << endl;
    return 0;
}
```

## 有依赖的背包问题

当使用物品间存在树形依赖关系, 需要用到树形dp.

- `f[i][j]`的定义将转变为 : **根节点为u的子树, 且选中节点u, 总体积不超过j的最大价值**.

至于为什么要选中节点u, 也是因为题目性质, 选中也可以方便计算, 因为如果不选中u, 那么它的所有子树也就不能选, 就没有意义了.

```cpp
#include<iostream>
#include<cstring>
#define rep(i, a, b) for(int i = (a); i <= (b); i ++ )
#define int long long 
using namespace std;
const int N = 210;
int n, m;
int h[N], e[N], ne[N], idx;
int v[N], w[N];
// 想选一定要选根节点, 所以无需担心不选中root的结果
int f[N][N]; // 根节点为u的子树, 且选中节点u, 总体积不超过j的最大价值

void add(int a, int b)
{
    e[idx] = b, ne[idx] = h[a], h[a] = idx++;
}

void dfs(int u)
{
    for(int i = h[u]; i != -1; i = ne[i])
    {
        int j = e[i];
        dfs(j); // 先往里走把前置子树都更新完
        
        // 每个子树做一次分组背包, 枚举当前子树不超过的体积[0, 100], 再枚举从该子树中选中多少体积
        for(int x = m - v[u]; x >= 0; x -- )
            for(int y = 0; y <= x; y ++ )
                f[u][x] = max(f[u][x], f[u][x - y] + f[j][y]); // 子树体积不超过x, 从该子树选中y体积总和物品
    }
    
    // 我们假定一定要选中u, 将分组背包的结果加上u
    for(int i = m; i >= v[u]; i -- ) f[u][i] = f[u][i - v[u]] + w[u];
    for(int i = 0; i < v[u]; i ++ ) f[u][i] = 0;
}

signed main()
{
    cin >> n >> m;
    memset(h, -1, sizeof h);
    
    int root;
    rep(i, 1, n)
    {
        int a, b, fa;
        cin >> a >> b >> fa;
        v[i] = a, w[i] = b;
        if(fa == -1) root = i;
        else add(fa, i);
    }
    
    dfs(root);
    
    cout << f[root][m] << endl;
    return 0;
}
```

这里分组背包相当于每次dfs得到的一个子树就是新的一组, 但当根节点想要知道子节点子树的答案是, 子节点可能很多如果枚举子节点的使用与否将是2的幂次级, n < 100, 2的100次有很大问题. 解决问题是不枚举状态, 改为枚举体积, 因为所有枚举的结果最后一定都会落在体积范围内, 也就是[0, 100].

所以先枚举根节点子树打算占用多少体积, 再枚举当前子节点子树打算占用多少体积, 就可以得到状态转移方程了.



