# 05: DinDサイドカー + Testcontainers対応

**What to build:** 本体コンテナから`docker`コマンドが使え、DinDサイドカー経由でPostgreSQL/Redis等のコンテナやTestcontainersベースのテストが動く。DinD内で起動したコンテナも02で敷いたネットワーク隔離ルールの内側に入り、ホストへは到達できない。

**Blocked by:** 01, 02

**Status:** ready-for-agent

- [ ] 本体コンテナ内から`docker`コマンドを実行すると、ネストされたDinDのDocker daemonに対して動作する
- [ ] Testcontainersベースのテスト（例: PostgreSQLやRedisを起動するテスト）がサンドボックス内で成功する
- [ ] Testcontainers/DinD経由で起動したコンテナも、ホストの`127.0.0.1`/`0.0.0.0`向けサービスに到達できない（02の隔離を継承していることの実証）
- [ ] DinD経由で起動したコンテナからインターネットへは到達できる（イメージのpull等が動く）
