---
title: Redis深入学习(3) 持久化 高可用 高扩展
date: 2025-11-01 19:44:00
tags: [Redis]
---

## 持久化

Redis作为缓存服务, 其快速高效的本质在于, 其服务都是在**内存**上执行的, 不想Mysql要刷到磁盘上, 搜索时还要搜盘. 

但这种方式的弊端在于只要服务器宕机, 这些内存上的数据直接消失, 因此Redis为了宕机后可以快速恢复数据并且不影响正常使用时的效率, 祭出了RDB和AOF两种持久化策略.

### RDB(快照读)

十分容易理解, 你可以理解为假定Redis上所有数据等于一个map, RDB就是把这个map**直接作为数据存入`.rdb`文件刷到磁盘中**, 恢复时直接读就行.

实际会走一个线程, 定时几分钟就刷一次, 这样不至于影响到运行效率.

### AOF(追加日志)

这是另一种数据恢复的方式, 即从头开始把所有指令存到`.aof`文件中, 在恢复时把所有指令重新执行一遍就等于复原了.

AOF的优势在于可以大体上没有遗漏地恢复所有数据, 但是劣势就很多了 : 

- 影响到服务运行效率, 需要频繁刷盘.
- `.aof`的大小在等量数据的情况下是`.rdb`文件的10倍不止, 十分占空间.
- 恢复数据时间极长, 方式是重新执行命令, 和直接用RDB恢复的时间差距非常大.

AOF也做了一定程度的补足 : 

- 当`.aof`文件大于一定大小后, 会进行**重写**, 会删去很多叠加或重复的命令, 比如先加上后删掉就直接等于没有, 可以减少文件大小.

### 混合持久化(RDB + AOF)

这是当前生产环境的主流用法. 其核心主要在于**用RDB优化AOF流程**.

- 上面纯AOF进行重写的方式是删减命令, 但是混合持久化中, AOF会直接将走RDB流程, **将当前数据对应的`.rdb`文件内容直接拷入`.aof`文件中**. 
- 之后再进行正常的AOF流程, 把新的命令刷到文件中.
- 所以这里恢复数据就是先读RDB部分, 还原出数据后再执行剩下AOF部分的命令, 效率会高不少.

注意这里上面说的AOF的后两个劣势可以解决, 但是第一个劣势无法解决, 所以依旧会影响效率.

- 虽然会损失部分效率, 目前还是大部分使用混合持久化, 小部分使用纯RDB, 毕竟数据缺失还是更可怕些.

- 目前Redis默认都是纯RDB, 如果想使用混合持久化需要进行配置, 并关闭RDB的独立线程. 可以在redis-cli中设置临时配置 : 

  ```bash
  # 开启 AOF 持久化
  CONFIG SET appendonly yes
  
  # 开启混合持久化（Redis 4.0+）
  CONFIG SET aof-use-rdb-preamble yes
  
  # 关闭独立 RDB 生成（禁止定时BGSAVE）
  CONFIG SET save ""
  
  # 设置 AOF 同步策略（默认 everysec 已够用）
  CONFIG SET appendfsync everysec
  
  # 检查配置是否生效
  CONFIG GET appendonly
  CONFIG GET aof-use-rdb-preamble
  CONFIG GET save
  ```

  也可以设置完永久保存配置 : 

  ```bash
  # 将临时配置写入 redis.conf（需 sudo 权限）
  sudo redis-cli config rewrite
  ```



## 高可用(主从 + 哨兵)

和上一章提到的RedLock的问题一样, 但是RedLock只关注于如何解决单机崩溃下分布式锁的问题, Redis高可用关注的是**单机崩溃下保证服务正常提供**的问题.

### 主从架构

一个服务器不行, 就多加几个, 里面有一个主节点, 多个从节点.

- 主节点 : **同时负责读写**, 并且持续向从节点发送自己接收写操作.
- 从节点 : **只负责读操作**, 可以通过反向代理减缓主节点的读操作负担, 并且随时为故障转移提供数据备份.

这样如果主节点挂了, 再选一个从节点成为主节点就行.

### Sentinel (哨兵模式)

旨在解决**监控节点健康状态及主节点挂后如何选择从节点**的问题.

解决方式 : 

- 开一个哨兵节点, 持续向主从节点发PING, **监控所有节点的健康状态**.
- 一旦主节点挂掉, 会**通知一个从节点成为主节点开始接收写操作**, 并且从节点的选择是会优先配置最好的以及和主节点同步最好的.
- 哨兵也可能挂, 所以一般要开多个哨兵节点, 它们之间会互通有无, 并且在选举从节点时统一意见.

### Redis服务配置实现

在进行主从和哨兵的实践前, 我认为还是需要明确在服务器上配置一个Redis服务分别需要什么文件夹 : 

- **conf** : 存储核心配置文件, 记录一个服务的关键信息.
- **data** : 存储rdb, aof等数据文件的存储.
- **log** : 存储每个redis服务运行过程中产生的日志.
- **run** : 存放pid文件, 用于服务管理, 进程监控.

另外Redis服务文件存放的位置也需要考虑, 如果只是练习可以直接放在用户目录下, 这样就没有任何权限问题了; 但是生产环境中为了安全, 一般会放在需要权限设置的地方, 我选择的路径是`/usr/local/redis`, 于是我通过以下指令构建需要的文件夹和权限设置 : 

```bash
# 1. 创建基础目录
REDIS_BASE="/usr/local/redis"
mkdir -p $REDIS_BASE/{conf,data,log,run}
chown -R redis:redis $REDIS_BASE
chmod 750 $REDIS_BASE

# 2. 创建节点目录
for port in 6381 6382; do
  mkdir -p $REDIS_BASE/data/$port
  chown redis:redis $REDIS_BASE/data/$port
  chmod 750 $REDIS_BASE/data/$port
done

# 3. 创建哨兵目录
for port in 26381 26382 26383; do
  mkdir -p $REDIS_BASE/data/sentinel-$port
  chown redis:redis $REDIS_BASE/data/sentinel-$port
  chmod 750 $REDIS_BASE/data/sentinel-$port
done

# 4. 设置日志和PID目录权限
chmod 770 $REDIS_BASE/log $REDIS_BASE/run

# 5. 创建配置文件
# 主节点配置
tee $REDIS_BASE/conf/master-6381.conf <<'EOF'
port 6381
daemonize yes
pidfile "/usr/local/redis/run/redis_6381.pid"
logfile "/usr/local/redis/log/redis-6381.log"
dir "/usr/local/redis/data/6381"
requirepass "111"
masterauth "111"
protected-mode no
EOF

# 从节点配置
tee $REDIS_BASE/conf/slave-6382.conf <<'EOF'
port 6382
daemonize yes
pidfile "/usr/local/redis/run/redis_6382.pid"
logfile "/usr/local/redis/log/redis-6382.log"
dir "/usr/local/redis/data/6382"
replicaof 127.0.0.1 6381
masterauth "111"
replica-read-only yes
protected-mode no
EOF

# 哨兵配置模板
SENTINEL_CONF="port %PORT%
daemonize yes
pidfile \"/usr/local/redis/run/sentinel_%PORT%.pid\"
logfile \"/usr/local/redis/log/sentinel-%PORT%.log\"
dir \"/usr/local/redis/data/sentinel-%PORT%\"
sentinel monitor mymaster 127.0.0.1 6381 2
sentinel auth-pass mymaster 111
sentinel down-after-milliseconds mymaster 5000
protected-mode no"

# 生成三个哨兵配置
for port in 26381 26382 26383; do
  echo "$SENTINEL_CONF" | sed "s/%PORT%/$port/g" > $REDIS_BASE/conf/sentinel-$port.conf
done

# 6. 设置文件权限
chmod 640 $REDIS_BASE/conf/*.conf
chown redis:redis $REDIS_BASE/conf/*.conf

# 7. 创建日志文件
for file in redis-6381 redis-6382 sentinel-26381 sentinel-26382 sentinel-26383; do
  touch $REDIS_BASE/log/$file.log
  chmod 660 $REDIS_BASE/log/$file.log
  chown redis:redis $REDIS_BASE/log/$file.log
done

# 8. 创建PID文件
for file in redis_6381 redis_6382 sentinel_26381 sentinel_26382 sentinel_26383; do
  touch $REDIS_BASE/run/$file.pid
  chmod 664 $REDIS_BASE/run/$file.pid
  chown redis:redis $REDIS_BASE/run/$file.pid
done
```

- 哨兵需要配置三个来实现哨兵集群.

于是我们就可以得到下面这样的结构 : 

```bash
➜  redis tree
.
├── conf
│   ├── master-6381.conf
│   ├── sentinel-26381.conf
│   ├── sentinel-26382.conf
│   ├── sentinel-26383.conf
│   └── slave-6382.conf
├── data
│   ├── 6381
│   │   └── dump.rdb
│   ├── 6382
│   │   └── dump.rdb
│   ├── sentinel-26381
│   ├── sentinel-26382
│   └── sentinel-26383
├── log
│   ├── redis-6381.log
│   ├── redis-6382.log
│   ├── sentinel-26381.log
│   ├── sentinel-26382.log
│   └── sentinel-26383.log
└── run
    ├── redis_6381.pid
    ├── redis_6382.pid
    ├── sentinel_26381.pid
    ├── sentinel_26382.pid
    └── sentinel_26383.pid
```

ps : 真的要把权限设置搞好, 不然如果哨兵要进行主从替换的话, 没权限写conf文件就G了. 

### 实际测试

- 启动主从服务 : 

  ```bash
  ➜  /etc sudo -u redis redis-server /etc/redis/master-6381.conf
  ➜  /etc redis-cli -p 6381 -a 111 PING
  PONG
  ➜  /etc sudo -u redis redis-server /etc/redis/slave-6382.conf
  ```

- 检查主从配置 : 

  ```cpp
  ➜  ~ redis-cli -p 6381 -a 111 INFO replication | grep -E "role|connected_slaves"
  role:master
  connected_slaves:1
  ➜  ~ redis-cli -p 6382 -a 111 INFO replication | grep -E "role|master_link_status"
  role:slave
  master_link_status:up
  ```

- 启动哨兵 + 测试宕机切换 + 验证新主节点 + 观察原主节点 : 

  ```bash
  //==============启动哨兵并查看集群 ===============//
  ➜  ~ sudo -u redis redis-server /etc/redis/sentinel-26381.conf --sentinel --daemonize yes
  ➜  ~ sudo -u redis redis-server /etc/redis/sentinel-26382.conf --sentinel --daemonize yes
  sudo -u redis redis-server /etc/redis/sentinel-26383.conf --sentinel --daemonize yes
  ➜  ~ redis-cli -p 26381 SENTINEL sentinels mymaster
  1)  1) "name"
      2) "01d4f8599256136219d677fa91ef5d8fabc85272"
      3) "ip"
      4) "127.0.0.1"
      5) "port"
      6) "26382"
      7) "runid"
      8) "01d4f8599256136219d677fa91ef5d8fabc85272"
      9) "flags"
     10) "sentinel,master_down"
     11) "link-pending-commands"
     12) "0"
     13) "link-refcount"
     14) "1"
     15) "last-ping-sent"
     16) "0"
     17) "last-ok-ping-reply"
     18) "786"
     19) "last-ping-reply"
     20) "786"
     21) "down-after-milliseconds"
     22) "5000"
     23) "last-hello-message"
     24) "744"
     25) "voted-leader"
     26) "?"
     27) "voted-leader-epoch"
     28) "0"
  2)  1) "name"
      2) "27de0adcf8c3614b8f415a4ce79f763d101214af"
      3) "ip"
      4) "127.0.0.1"
      5) "port"
      6) "26383"
      7) "runid"
      8) "27de0adcf8c3614b8f415a4ce79f763d101214af"
      9) "flags"
     10) "sentinel,master_down"
     11) "link-pending-commands"
     12) "0"
     13) "link-refcount"
     14) "1"
     15) "last-ping-sent"
     16) "0"
     17) "last-ok-ping-reply"
     18) "786"
     19) "last-ping-reply"
     20) "786"
     21) "down-after-milliseconds"
     22) "5000"
     23) "last-hello-message"
     24) "740"
     25) "voted-leader"
     26) "?"
     27) "voted-leader-epoch"
     28) "0"
  
  //==============  测试宕机切换 ================//
  ➜  ~ redis-cli -p 6381 -a 111 SHUTDOWN
  ➜  ~ sudo tail -f /var/log/redis/sentinel-26381.log
  2002404:X 27 Oct 2025 20:58:44.443 * Sentinel new configuration saved on disk
  2002404:X 27 Oct 2025 20:58:44.444 # +new-epoch 3
  2002404:X 27 Oct 2025 20:58:44.449 * Sentinel new configuration saved on disk
  2002404:X 27 Oct 2025 20:58:44.449 # +vote-for-leader 27de0adcf8c3614b8f415a4ce79f763d101214af 3
  //--------------确认到主节点下线----------------//
  2002404:X 27 Oct 2025 20:58:45.423 # +odown master mymaster 127.0.0.1 6381 #quorum 3/2
  2002404:X 27 Oct 2025 20:58:45.423 # Next failover delay: I will not start a failover before Mon Oct 27 21:04:45 2025
  2002404:X 27 Oct 2025 20:58:45.529 # +config-update-from sentinel 27de0adcf8c3614b8f415a4ce79f763d101214af 127.0.0.1 26383 @ mymaster 127.0.0.1 6381
  //---------成功将主节点从6381切换为6382----------//
  2002404:X 27 Oct 2025 20:58:45.529 # +switch-master mymaster 127.0.0.1 6381 127.0.0.1 6382
  //-------------6381被标记为从节点---------------//
  2002404:X 27 Oct 2025 20:58:45.529 * +slave slave 127.0.0.1:6381 127.0.0.1 6381 @ mymaster 127.0.0.1 6382
  2002404:X 27 Oct 2025 20:58:45.536 * Sentinel new configuration saved on disk
  2002404:X 27 Oct 2025 20:58:50.551 # +sdown slave 127.0.0.1:6381 127.0.0.1 6381 @ mymaster 127.0.0.1 6382
  
  //==============验证新主节点================//
  ➜  ~ redis-cli -p 26381 SENTINEL get-master-addr-by-name mymaster
  1) "127.0.0.1"
  2) "6382"
  ➜  ~ redis-cli -p 6382 INFO replication | grep role
  role:master
  
  //==============观察原主节点================//
  ➜  ~ sudo -u redis redis-server /etc/redis/master-6381.conf
  ➜  ~ redis-cli -p 6381 -a 111 INFO replication | grep -E "role|master_host"
  role:slave
  master_host:127.0.0.1
  master_port:6382
  ```

这样就算基本测试完毕了, 哨兵观察到主机宕机后选举从节点为新的主机, 不过貌似想要让原主节点降级, 还要配置宕机节点的自启动, 重新启动后哨兵检测到才会进行降级, 这里学习的时间已经有点多了, 就不继续深入了. 

- 后面要学习的Redis的Cluster虽然也兼具高可用, 但是哨兵模式实现的高可用更专精更精简, 并且支持所有Redis命令(比如事务, Lua, 跨key操作), 而Cluster由于本身多节点的形式会对部分命令不适用.



## 高扩展(集群)

### 初步理解

- **单机内存有限, 数据无限**, 因此像是我们上面的高可用方案, 只要数据量上去, 到达单机内存上限后就回天乏术了, 多台机子也只是存相同的数据而已.
- 解决方式很容易理解, **多准备一些高可用节点, 不同节点存不同的数据**, 这种行为一般被称为**数据切片**, 初步具备集群的形态.
- 但是这种集群的形式又会带来另一种问题, 其作为统一的服务, **如何实现精准的查询到对应key究竟存在哪个节点上了呢**? 总不可能到每个节点上都查一下.
- 用**哈希**就可以了!  **目标节点编号 = CRC(key) % Redis节点数**, 这样每次哈希一下就可以马上精确找到对应节点了.

### 核心问题

上面的方式只能实现所谓的"扩展", 而不是"高扩展", 最后的效果也只是从一个单机的容量变为几个单机的容量的罢了.

我们想实现的是, **根据当前数据存量动态的增加Redis节点**, 你也许会认为上面的方法也可行, 但是**如果Redis节点数发生变动, 那么哈希算式就会根本性改变, 以前的key也未必会算到原本存放的节点**.

你也许还会认为, 如果发生变动就把发生改变的数据再迁移到正确的节点, 这迁移的数量一定是相当大的, 可以理解为牵一发而动全身, 而且迁移本身需要事件, 也有中途出错的风险, 是非常危险的.

### 一致性哈希

- 本人并没有认真学过一致性哈希的细节, 这里只是简单说明Redis是如果应用一致性哈希的.

- 解决方式还是相对简单, 就是既然哈希算式会变, 我们让它不变就行, 我们把Redis节点数用一个大数替换.
- **目标节点编号 = CRC(key) % 16384**(2 ^ 14), 这样算式就永远不变了.
- 但是我们没有16384个节点, 而且动态怎么实现呢? 答案是**加一层中间层**, 我们一般叫**哈希槽**.
- 类似于维护一个16384大小的数组, 平均分配当前的实际的节点编号, 如果只有两个节点, 那么一般就是1~8192为0, 8193~16384为1. 
- 这样算出来的哈希值去哈希槽里去取对应的实际节点编号就行了.
- 想要动态增加节点, 就可以修改哈希槽, 然后分裂某个Redis节点对应的范围, 然后将这个节点中需要迁移到新节点的少量数据迁过去就行.
- 那么原本动态增加Redis节点需要产生的影响, 就从**哈希算式改变 + 多Redis节点大量数据迁移**, 变为了**哈希槽改变 + 单Redis节点少量数据迁移**, 让动态增加节点的风险变得极为可控.

### 重定向

- 其实**并没有客户端拿着哈希值去哈希槽获取节点编号的行为, 而实际是客户端自己维护一个哈希槽映射**, 记录有几个节点及对应范围.
- **每个Redis节点也都会维护自己认知中的哈希槽映射**.
- 一开始客户端没有哈希槽映射时, 就会随便找一个节点获取, 随后如果某些节点的映射发生变化, 与客户端的映射发生冲突, 也就是客户端找错了, 那么这个节点就会**把其维护的映射发给客户端让其更新**, **并且重新找到正确的目标节点**, 这种操作叫做**重定向**.
- 必要性 : 客户端和各个节点本身都是在不同的服务器上, 如果发生变动服务器之间就会发生信息差, 如果没有及时更新就会发生冲突, 重定向就是为了解决这种冲突下实现的机制, 并且也一定程度上降低了数据互通的成本.

### Redis Cluster 实际部署

和哨兵模式的配置方式也类似, 但是这次配置的特别顺利, 居然一次就过了, 感觉比哨兵好配很多...

我本次直接就是在家目录下建的, 就没有搞权限设置了.

- 构建目录

  ```bash
  ➜  ~ mkdir redis-cluster
  cd redis-cluster
  ➜  redis-cluster mkdir node-7000 node-7001 node-7002 node-7003 node-7004 node-7005
  ➜  redis-cluster tree
  .
  ├── node-7000
  ├── node-7001
  ├── node-7002
  ├── node-7003
  ├── node-7004
  └── node-7005
  ```

- 构建集群配置文件

  ```bash
  ➜  redis-cluster cat > redis-cluster-base.conf << 'EOF'
  # 基本配置
  port 7000
  daemonize yes
  pidfile /home/your_username/redis-cluster/node-7000/redis.pid
  logfile "/home/your_username/redis-cluster/node-7000/redis.log"
  dir /home/your_username/redis-cluster/node-7000/
  # 持久化
  appendonly yes
  appendfilename "appendonly.aof"
  # 集群配置
  cluster-enabled yes
  cluster-config-file nodes.conf
  cluster-node-timeout 15000
  # 安全设置（可选，但生产环境建议设置）
  # requirepass your_strong_password
  # masterauth your_strong_password
  # 性能优化
  stop-writes-on-bgsave-error no
  rdbcompression yes
  rdbchecksum yes
  dbfilename dump.rdb
  EOF
  ```

- 继续准备配置文件

  ```bash
  ➜  redis-cluster CURRENT_USER=$(whoami)
  ➜  redis-cluster sed -i "s/your_username/$CURRENT_USER/g" redis-cluster-base.conf
  ➜  redis-cluster for port in 7000 7001 7002 7003 7004 7005; do
    cp redis-cluster-base.conf node-${port}/redis.conf
    sed -i "s/7000/${port}/g" node-${port}/redis.conf
  done
  ➜  redis-cluster # 检查一个节点的配置是否正确
  cat node-7000/redis.conf | grep -E "(port|pidfile|dir)"
  port 7000
  pidfile /home/lth/redis-cluster/node-7000/redis.pid
  dir /home/lth/redis-cluster/node-7000/
  ```

- 启动节点

  ```cpp
  ➜  redis-cluster for port in 7000 7001 7002 7003 7004 7005; do
    echo "启动节点 ${port}..."
    redis-server node-${port}/redis.conf
  done
  启动节点 7000...
  启动节点 7001...
  启动节点 7002...
  启动节点 7003...
  启动节点 7004...
  启动节点 7005...
  ```

- 启动集群

  ```bash
  ➜  redis-cluster redis-cli --cluster create \
    127.0.0.1:7000 127.0.0.1:7001 127.0.0.1:7002 \
    127.0.0.1:7003 127.0.0.1:7004 127.0.0.1:7005 \
    --cluster-replicas 1
  >>> Performing hash slots allocation on 6 nodes...
  Master[0] -> Slots 0 - 5460
  Master[1] -> Slots 5461 - 10922
  Master[2] -> Slots 10923 - 16383
  Adding replica 127.0.0.1:7004 to 127.0.0.1:7000
  Adding replica 127.0.0.1:7005 to 127.0.0.1:7001
  Adding replica 127.0.0.1:7003 to 127.0.0.1:7002
  >>> Trying to optimize slaves allocation for anti-affinity
  [WARNING] Some slaves are in the same host as their master
  M: dbe2fc4733f551b9550b0a3d6cb5ca2bdeeb1eeb 127.0.0.1:7000
     slots:[0-5460] (5461 slots) master
  M: 40347f4075e504d54aac27dbc6b6181af81ea3eb 127.0.0.1:7001
     slots:[5461-10922] (5462 slots) master
  M: a26cc56bcf50fd347087c76261e7e5a8a26e9dc8 127.0.0.1:7002
     slots:[10923-16383] (5461 slots) master
  S: 371e9c58141b0ed8b58a447ff15f977e2b5e8282 127.0.0.1:7003
     replicates dbe2fc4733f551b9550b0a3d6cb5ca2bdeeb1eeb
  S: de1432e6acdc67122b2626164b16e8ddf1950a7f 127.0.0.1:7004
     replicates 40347f4075e504d54aac27dbc6b6181af81ea3eb
  S: 87dba4c3fe16a835cd39e424ac79e8f618411609 127.0.0.1:7005
     replicates a26cc56bcf50fd347087c76261e7e5a8a26e9dc8
  Can I set the above configuration? (type 'yes' to accept): yes
  >>> Nodes configuration updated
  >>> Assign a different config epoch to each node
  >>> Sending CLUSTER MEET messages to join the cluster
  Waiting for the cluster to join
  .
  >>> Performing Cluster Check (using node 127.0.0.1:7000)
  M: dbe2fc4733f551b9550b0a3d6cb5ca2bdeeb1eeb 127.0.0.1:7000
     slots:[0-5460] (5461 slots) master
     1 additional replica(s)
  M: a26cc56bcf50fd347087c76261e7e5a8a26e9dc8 127.0.0.1:7002
     slots:[10923-16383] (5461 slots) master
     1 additional replica(s)
  S: 87dba4c3fe16a835cd39e424ac79e8f618411609 127.0.0.1:7005
     slots: (0 slots) slave
     replicates a26cc56bcf50fd347087c76261e7e5a8a26e9dc8
  M: 40347f4075e504d54aac27dbc6b6181af81ea3eb 127.0.0.1:7001
     slots:[5461-10922] (5462 slots) master
     1 additional replica(s)
  S: de1432e6acdc67122b2626164b16e8ddf1950a7f 127.0.0.1:7004
     slots: (0 slots) slave
     replicates 40347f4075e504d54aac27dbc6b6181af81ea3eb
  S: 371e9c58141b0ed8b58a447ff15f977e2b5e8282 127.0.0.1:7003
     slots: (0 slots) slave
     replicates dbe2fc4733f551b9550b0a3d6cb5ca2bdeeb1eeb
  [OK] All nodes agree about slots configuration.
  >>> Check for open slots...
  >>> Check slots coverage...
  [OK] All 16384 slots covered.
  ```

- 检查集权状态并测试

  ```cpp
  ➜  redis-cluster redis-cli -p 7000 cluster info
  cluster_state:ok
  cluster_slots_assigned:16384
  cluster_slots_ok:16384
  cluster_slots_pfail:0
  cluster_slots_fail:0
  cluster_known_nodes:6
  cluster_size:3
  cluster_current_epoch:6
  cluster_my_epoch:1
  cluster_stats_messages_ping_sent:41
  cluster_stats_messages_pong_sent:43
  cluster_stats_messages_sent:84
  cluster_stats_messages_ping_received:38
  cluster_stats_messages_pong_received:41
  cluster_stats_messages_meet_received:5
  cluster_stats_messages_received:84
  total_cluster_links_buffer_limit_exceeded:0
  ➜  redis-cluster redis-cli -p 7000 cluster nodes
  a26cc56bcf50fd347087c76261e7e5a8a26e9dc8 127.0.0.1:7002@17002 master - 0 1761992047993 3 connected 10923-16383
  87dba4c3fe16a835cd39e424ac79e8f618411609 127.0.0.1:7005@17005 slave a26cc56bcf50fd347087c76261e7e5a8a26e9dc8 0 1761992048996 3 connected
  dbe2fc4733f551b9550b0a3d6cb5ca2bdeeb1eeb 127.0.0.1:7000@17000 myself,master - 0 1761992048000 1 connected 0-5460
  40347f4075e504d54aac27dbc6b6181af81ea3eb 127.0.0.1:7001@17001 master - 0 1761992047000 2 connected 5461-10922
  de1432e6acdc67122b2626164b16e8ddf1950a7f 127.0.0.1:7004@17004 slave 40347f4075e504d54aac27dbc6b6181af81ea3eb 0 1761992046000 2 connected
  371e9c58141b0ed8b58a447ff15f977e2b5e8282 127.0.0.1:7003@17003 slave dbe2fc4733f551b9550b0a3d6cb5ca2bdeeb1eeb 0 1761992046000 1 connected
  ➜  redis-cluster redis-cli -p 7000 -c set hello "world"
  redis-cli -p 7000 -c get hello
  OK
  "world"
  ```

- 测试动态增加主从节点

  ```bash
  # 构建并运行新主从节点
  ➜  redis-cluster mkdir node-7006 node-7007
  ➜  redis-cluster for port in 7006 7007; do
    cp node-7000/redis.conf node-${port}/
    sed -i "s/7000/${port}/g" node-${port}/redis.conf
    sed -i "s/node-7000/node-${port}/g" node-${port}/redis.conf
  done
  ➜  redis-cluster cat node-7006/redis.conf | grep -E "(port|pidfile|dir)"
  port 7006
  pidfile /home/lth/redis-cluster/node-7006/redis.pid
  dir /home/lth/redis-cluster/node-7006/
  ➜  redis-cluster redis-server node-7006/redis.conf
  redis-server node-7007/redis.conf
  ➜  redis-cluster ps aux | grep redis-server | grep -E "(7006|7007)"
  lth      3416010  0.0  0.3  67864  6876 ?        Ssl  18:45   0:00 redis-server *:7006 [cluster]
  lth      3416016  0.0  0.3  67864  6996 ?        Ssl  18:45   0:00 redis-server *:7007 [cluster]
  
  # 将主节点加入集群
  ➜  redis-cluster redis-cli --cluster add-node 127.0.0.1:7006 127.0.0.1:7000
  >>> Adding node 127.0.0.1:7006 to cluster 127.0.0.1:7000
  >>> Performing Cluster Check (using node 127.0.0.1:7000)
  S: dbe2fc4733f551b9550b0a3d6cb5ca2bdeeb1eeb 127.0.0.1:7000
     slots: (0 slots) slave
     replicates 371e9c58141b0ed8b58a447ff15f977e2b5e8282
  S: de1432e6acdc67122b2626164b16e8ddf1950a7f 127.0.0.1:7004
     slots: (0 slots) slave
     replicates 40347f4075e504d54aac27dbc6b6181af81ea3eb
  M: a26cc56bcf50fd347087c76261e7e5a8a26e9dc8 127.0.0.1:7002
     slots:[10923-16383] (5461 slots) master
     1 additional replica(s)
  M: 371e9c58141b0ed8b58a447ff15f977e2b5e8282 127.0.0.1:7003
     slots:[0-5460] (5461 slots) master
     1 additional replica(s)
  S: 87dba4c3fe16a835cd39e424ac79e8f618411609 127.0.0.1:7005
     slots: (0 slots) slave
     replicates a26cc56bcf50fd347087c76261e7e5a8a26e9dc8
  M: 40347f4075e504d54aac27dbc6b6181af81ea3eb 127.0.0.1:7001
     slots:[5461-10922] (5462 slots) master
     1 additional replica(s)
  [OK] All nodes agree about slots configuration.
  >>> Check for open slots...
  >>> Check slots coverage...
  [OK] All 16384 slots covered.
  >>> Getting functions from cluster
  >>> Send FUNCTION LIST to 127.0.0.1:7006 to verify there is no functions in it
  >>> Send FUNCTION RESTORE to 127.0.0.1:7006
  >>> Send CLUSTER MEET to node 127.0.0.1:7006 to make it join the cluster.
  [OK] New node added correctly.
  ➜  redis-cluster redis-cli -p 7000 cluster nodes | grep 7006
  e1879e1438545179f139904ab663a9513b4a7511 127.0.0.1:7006@17006 master - 0 1761994053333 0 connected
  
  # 执行重新分配
  ➜  redis-cluster redis-cli --cluster reshard 127.0.0.1:7000
  >>> Performing Cluster Check (using node 127.0.0.1:7000)
  S: dbe2fc4733f551b9550b0a3d6cb5ca2bdeeb1eeb 127.0.0.1:7000
     slots: (0 slots) slave
     replicates 371e9c58141b0ed8b58a447ff15f977e2b5e8282
  M: e1879e1438545179f139904ab663a9513b4a7511 127.0.0.1:7006
     slots: (0 slots) master
  S: de1432e6acdc67122b2626164b16e8ddf1950a7f 127.0.0.1:7004
     slots: (0 slots) slave
     replicates 40347f4075e504d54aac27dbc6b6181af81ea3eb
  M: a26cc56bcf50fd347087c76261e7e5a8a26e9dc8 127.0.0.1:7002
     slots:[10923-16383] (5461 slots) master
     1 additional replica(s)
  M: 371e9c58141b0ed8b58a447ff15f977e2b5e8282 127.0.0.1:7003
     slots:[0-5460] (5461 slots) master
     1 additional replica(s)
  S: 87dba4c3fe16a835cd39e424ac79e8f618411609 127.0.0.1:7005
     slots: (0 slots) slave
     replicates a26cc56bcf50fd347087c76261e7e5a8a26e9dc8
  M: 40347f4075e504d54aac27dbc6b6181af81ea3eb 127.0.0.1:7001
     slots:[5461-10922] (5462 slots) master
     1 additional replica(s)
  [OK] All nodes agree about slots configuration.
  >>> Check for open slots...
  >>> Check slots coverage...
  [OK] All 16384 slots covered.
  How many slots do you want to move (from 1 to 16384)? 4096
  What is the receiving node ID? 7^H^[[B
  *** The specified node () is not known or not a master, please retry.
  ➜  redis-cluster redis-cli --cluster reshard 127.0.0.1:7000                
  >>> Performing Cluster Check (using node 127.0.0.1:7000)
  S: dbe2fc4733f551b9550b0a3d6cb5ca2bdeeb1eeb 127.0.0.1:7000
     slots: (0 slots) slave
     replicates 371e9c58141b0ed8b58a447ff15f977e2b5e8282
  M: e1879e1438545179f139904ab663a9513b4a7511 127.0.0.1:7006
     slots: (0 slots) master
  S: de1432e6acdc67122b2626164b16e8ddf1950a7f 127.0.0.1:7004
     slots: (0 slots) slave
     replicates 40347f4075e504d54aac27dbc6b6181af81ea3eb
  M: a26cc56bcf50fd347087c76261e7e5a8a26e9dc8 127.0.0.1:7002
     slots:[10923-16383] (5461 slots) master
     1 additional replica(s)
  M: 371e9c58141b0ed8b58a447ff15f977e2b5e8282 127.0.0.1:7003
     slots:[0-5460] (5461 slots) master
     1 additional replica(s)
  S: 87dba4c3fe16a835cd39e424ac79e8f618411609 127.0.0.1:7005
     slots: (0 slots) slave
     replicates a26cc56bcf50fd347087c76261e7e5a8a26e9dc8
  M: 40347f4075e504d54aac27dbc6b6181af81ea3eb 127.0.0.1:7001
     slots:[5461-10922] (5462 slots) master
     1 additional replica(s)
  [OK] All nodes agree about slots configuration.
  >>> Check for open slots...
  >>> Check slots coverage...
  [OK] All 16384 slots covered.
  How many slots do you want to move (from 1 to 16384)? 4096
  What is the receiving node ID? e1879e1438545179f139904ab663a9513b4a7511
  Please enter all the source node IDs.
    Type 'all' to use all the nodes as source nodes for the hash slots.
    Type 'done' once you entered all the source nodes IDs.
  Source node #1: all
  # .........
  
  # 将从节点加入集群
  ➜  redis-cluster redis-cli --cluster add-node 127.0.0.1:7007 127.0.0.1:7000 --cluster-slave --cluster-master-id e1879e1438545179f139904ab663a9513b4a7511
  >>> Adding node 127.0.0.1:7007 to cluster 127.0.0.1:7000
  >>> Performing Cluster Check (using node 127.0.0.1:7000)
  S: dbe2fc4733f551b9550b0a3d6cb5ca2bdeeb1eeb 127.0.0.1:7000
     slots: (0 slots) slave
     replicates 371e9c58141b0ed8b58a447ff15f977e2b5e8282
  M: e1879e1438545179f139904ab663a9513b4a7511 127.0.0.1:7006
     slots:[0-1364],[5461-6826],[10923-12287] (4096 slots) master
  S: de1432e6acdc67122b2626164b16e8ddf1950a7f 127.0.0.1:7004
     slots: (0 slots) slave
     replicates 40347f4075e504d54aac27dbc6b6181af81ea3eb
  M: a26cc56bcf50fd347087c76261e7e5a8a26e9dc8 127.0.0.1:7002
     slots:[12288-16383] (4096 slots) master
     1 additional replica(s)
  M: 371e9c58141b0ed8b58a447ff15f977e2b5e8282 127.0.0.1:7003
     slots:[1365-5460] (4096 slots) master
     1 additional replica(s)
  S: 87dba4c3fe16a835cd39e424ac79e8f618411609 127.0.0.1:7005
     slots: (0 slots) slave
     replicates a26cc56bcf50fd347087c76261e7e5a8a26e9dc8
  M: 40347f4075e504d54aac27dbc6b6181af81ea3eb 127.0.0.1:7001
     slots:[6827-10922] (4096 slots) master
     1 additional replica(s)
  [OK] All nodes agree about slots configuration.
  >>> Check for open slots...
  >>> Check slots coverage...
  [OK] All 16384 slots covered.
  >>> Send CLUSTER MEET to node 127.0.0.1:7007 to make it join the cluster.
  Waiting for the cluster to join
  
  >>> Configure node as replica of 127.0.0.1:7006.
  [OK] New node added correctly.
  
  # 验证集群状态
  ➜  redis-cluster redis-cli -p 7000 cluster nodes | wc -l
  8
  ➜  redis-cluster redis-cli -p 7000 cluster slots
  1) 1) (integer) 0
     2) (integer) 1364
     3) 1) "127.0.0.1"
        2) (integer) 7006
        3) "e1879e1438545179f139904ab663a9513b4a7511"
        4) (empty array)
     4) 1) "127.0.0.1"
        2) (integer) 7007
        3) "ce903b76943aa2daf257fa017fc0f0343073581e"
        4) (empty array)
  2) 1) (integer) 1365
     2) (integer) 5460
     3) 1) "127.0.0.1"
        2) (integer) 7003
        3) "371e9c58141b0ed8b58a447ff15f977e2b5e8282"
        4) (empty array)
     4) 1) "127.0.0.1"
        2) (integer) 7000
        3) "dbe2fc4733f551b9550b0a3d6cb5ca2bdeeb1eeb"
        4) (empty array)
  3) 1) (integer) 5461
     2) (integer) 6826
     3) 1) "127.0.0.1"
        2) (integer) 7006
        3) "e1879e1438545179f139904ab663a9513b4a7511"
        4) (empty array)
     4) 1) "127.0.0.1"
        2) (integer) 7007
        3) "ce903b76943aa2daf257fa017fc0f0343073581e"
        4) (empty array)
  4) 1) (integer) 6827
     2) (integer) 10922
     3) 1) "127.0.0.1"
        2) (integer) 7001
        3) "40347f4075e504d54aac27dbc6b6181af81ea3eb"
        4) (empty array)
     4) 1) "127.0.0.1"
        2) (integer) 7004
        3) "de1432e6acdc67122b2626164b16e8ddf1950a7f"
        4) (empty array)
  5) 1) (integer) 10923
     2) (integer) 12287
     3) 1) "127.0.0.1"
        2) (integer) 7006
        3) "e1879e1438545179f139904ab663a9513b4a7511"
        4) (empty array)
     4) 1) "127.0.0.1"
        2) (integer) 7007
        3) "ce903b76943aa2daf257fa017fc0f0343073581e"
        4) (empty array)
  6) 1) (integer) 12288
     2) (integer) 16383
     3) 1) "127.0.0.1"
        2) (integer) 7002
        3) "a26cc56bcf50fd347087c76261e7e5a8a26e9dc8"
        4) (empty array)
     4) 1) "127.0.0.1"
        2) (integer) 7005
        3) "87dba4c3fe16a835cd39e424ac79e8f618411609"
        4) (empty array)
  ```

  我们可以看到里面有一些关键的操作, 我们来分析一下 : 

  - `redis-cli --cluster add-node 127.0.0.1:7006 127.0.0.1:7000` : 

    通过`add-node`将主节点加入7000所在的集群.

  - `redis-cli --cluster add-node 127.0.0.1:7007 127.0.0.1:7000 --cluster-slave --cluster-master-id e1879e1438545179f139904ab663a9513b4a7511` : 

    使用`--cluster-slave`和`--cluster-master-id`表明作为从节点加入集群, 并且用id指定主节点.

  - `redis-cli -p 7000 cluster nodes | grep 7006` : 

    可以通过该指令获取7006在集群中对应的id, 用于上面加入从节点或下面指定分片目标.

  - `redis-cluster redis-cli --cluster reshard 127.0.0.1:7000`

    通过`reshard`执行重新分片, 只有通过该操作才可以真正加入集群, 我这里是通过程序的询问交互输入, 其实等效于下面的命令 :

    ```bash
    redis-cli --cluster reshard 127.0.0.1:7000 \
        --cluster-from all \
        --cluster-to e1879e1438545179f139904ab663a9513b4a7511 \
        --cluster-slots 4096 \
        --cluster-yes \
        --cluster-timeout 60000
    ```

    表示从所有节点平分槽范围到自己身上, 共迁移4096个, 自动确认.

### 关于数据分片的想法

- 怎么分是一个比可以思考问题, 像上面全部平分每个节点范围固然很公平, 但越到后面会越碎片化, 并且也不一定符合实际情况.
- 实际上是会发生某个节点负载过高的情况(二八定律)的,所以其实可以**筛选部分热点缓存, 新节点专门去分热点缓存持有率高的节点的范围**, 可以比较精确地解决Redis缓存服务的压力, 当然应该还可以深挖很多操作.

### 关于客户端对Redis集群执行命令

这里确实不能像之前访问一个Redis节点一样去访问集群, 还是需要用新的API去访问的, 这里`hiredis`库并没有对集群做很好的集成, 我打算在`redis-plus-plus`这个第三方库上进行实践, 另外也做些其他的操作, 这部分就放在下一章测试吧.



by 天目中云







