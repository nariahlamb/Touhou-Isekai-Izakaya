# 《东方异界食堂》技术设计文档 (Technical Design Document)

> 最后更新时间: 2025-12-21
> 状态: Beta Phase 5 (Refined Management & Map System)

## 1. 项目概览 (Overview)

**《东方异界食堂》** 是一款基于《东方Project》世界观的 LLM 驱动型 Web 角色扮演与经营游戏。
本项目旨在探索“文本驱动游戏”的新形态，通过 LLM 生成核心剧情，辅以可视化的状态面板、动态瓦片地图和模拟经营玩法，提供比传统 MUD 更直观、比传统 RPG 更自由的游戏体验。

### 1.1 核心理念
*   **文本为核，视觉为辅**：游戏的核心驱动力是 AI 生成的文本，UI 仅作为状态的投影。
*   **数据抽象化**：所有的游戏状态（HP、好感度、物品、位置、店铺营收）都抽象为变量，由 LLM 理解并由程序维护。
*   **多模型协作**：将“创意”、“逻辑”、“记忆”、“工具”拆解为多个独立的 LLM 任务，互不干扰。

---

## 2. 核心系统架构 (Core Architecture)

### 2.1 四重 LLM 协作架构 (The Quartet Architecture)

系统将任务分发给四个独立的 LLM 配置（支持分别配置 API/Model，也可以继承全局配置）：

| 模型 ID | 角色 | 职责 | 输入/输出 | 实现服务 |
| :--- | :--- | :--- | :--- | :--- |
| **LLM #1** | **Storyteller**<br>(对话模型) | 负责扮演 NPC，生成自然语言对话，推进剧情。 | **In:** Prompt (System + Memory + User Input)<br>**Out:** 剧情文本 (Streamed) + XML Triggers | `services/gameLoop.ts`<br>`services/prompt.ts` |
| **LLM #2** | **Game Master**<br>(逻辑模型) | 负责分析剧情，提取状态变更，生成快捷回复。 | **In:** 状态快照 + 剧情文本<br>**Out:** 结构化指令 (JSON) | `services/logic.ts` |
| **LLM #3** | **Scribe**<br>(记忆模型) | 负责长对话的摘要、关键信息提取与向量化记忆检索。 | **In:** 原始对话历史<br>**Out:** 记忆摘要 (Summary) | `services/memory.ts` |
| **LLM #4** | **Misc / Tool**<br>(杂项模型) | 负责非标准逻辑的杂项任务，如战斗中的“嘴遁”判定、**瓦片地图生成**。 | **In:** 特定任务上下文<br>**Out:** 结构化数据 (JSON) | `services/combatLogic.ts`<br>`services/management/MapGenerator.ts` |

#### 2.1.1 逻辑处理流 (Logic Flow)
采用 **"Intent-Execution"** 模式与 **"Parallel Processing"** 优化：
1.  **User Input**: 用户发送消息。
2.  **LLM #1 Generation**: 生成剧情文本，并可能包含 `<combat_trigger>`, `<quest_trigger>` 等 XML 标签。
3.  **Immediate Commit**: 剧情生成完毕后，立即作为 Assistant Message 上屏并保存。
4.  **Background Processing (Async)**:
    *   **Logic Analysis (LLM #2)**: 分析剧情，输出 JSON 指令（如 `UPDATE_PLAYER`, `UPDATE_NPC`）。
    *   **State Application**: 前端 TypeScript 代码执行指令，更新 `Pinia Store`。
    *   **Snapshot Update**: 将更新后的状态回写到当前消息的快照中。
    *   **Memory Extraction (LLM #3)**: 异步提取本轮对话的关键记忆。

### 2.2 协议与触发器 (Protocols & Triggers)

Storyteller (LLM #1) 通过嵌入 XML 标签与系统进行交互：

*   **`<combat_trigger>`**: 触发战斗。包含敌人信息、战斗类型。
*   **`<quest_trigger>`**: 发布新任务。包含任务 ID、名称、要求、奖励。
*   **`<quest_update>`**: 更新任务状态（完成/失败）。
*   **`<promise_trigger>`**: 触发日常约定。
*   **`<promise_update>`**: 更新约定状态（达成/失效）。
*   **`<prediction_trigger>`**: 预测下一轮登场角色，用于优化 Prompt 构建。

### 2.3 战斗系统 (Combat System)

采用 **回合制战斗 (Turn-based)**，支持符卡、道具、攻击和嘴遁。

#### 2.3.1 嘴遁系统 (Talk/Persuasion)
*   **机制**: 玩家输入一段文本，试图说服或动摇敌人。
*   **判定**: 调用 **LLM #4 (Misc)** 扮演裁判，分析输入内容与当前战况。
*   **效果**: 造成精神伤害、自我恢复、施加状态或直接胜利。

### 2.4 经营与地图系统 (Management & Map System)

新增的模拟经营模块，允许玩家装修和经营居酒屋。

#### 2.4.1 瓦片地图生成 (Procedural Map Generation)
*   **生成器**: `services/management/MapGenerator.ts`
*   **混合算法 (Hybrid Algorithm)**: 结合 LLM 的语义理解与传统算法的规则约束。
*   **核心优化**:
    *   **区域整合 (Zone Consolidation)**: 通过 Prompt 约束，强制 LLM 生成大块连续区域，避免地图碎片化（如避免生成多个 3x3 小房间）。
    *   **最小尺寸约束**: 强制功能区（K, D, L, B）最小尺寸为 4x4，确保扣除墙壁后仍有可用内部空间。
    *   **单层墙体**: 强制生成单层厚度墙体（`#`），最大化内部空间利用率。
*   **Phase 1: 语义分区 (Zoning Phase)**
    *   调用 **LLM #4** 生成“区域分布图 (Zone Map)”。
    *   **Zone Symbols**: `K` (Kitchen), `D` (Dining), `W` (Walkway), `E` (Entrance), `B` (Bedroom), `L` (Lounge)。
*   **Phase 2: 算法填充 (Population Phase)**
    *   **`services/management/ZonePopulator.ts`**: 根据 Zone Map 自动填充具体家具。
    *   **Kitchen (K)**: 
        *   **Boundary Classification**: 自动识别 Front (临接 Dining/Walkway) 和 Back (临接墙壁) 边界。
        *   **吧台生成**: 强制在 Front 边界生成连续的吧台（Counter），并保留唯一入口。
        *   **设施布局**: 优先在 Back 区域生成厨具（`O` Oven, `B` Bowl Stack, `S` Serving Table x3），确保内部通道（Internal Aisle）畅通。
    *   **Dining (D)**: 自动生成桌椅组合 `T + h`，保证行列整齐。
    *   **Walkway (W)**: 保持净空，确保 AI 生成的主干道不被阻挡。
    *   **Walls**: 自动识别外墙，随机生成窗户 `W`。
    *   **Stairs**: 自动识别顶层走廊生成楼梯 `H`。
*   **连通性校验**:
    *   **Flood Fill**: 验证玩家是否能从 Spawn 点到达所有关键区域（Exit, Kitchen）。
*   **多楼层支持**:
    *   支持 Ground Floor 与 Upper Floors 的差异化生成（如仅一楼有出口，高层有楼梯衔接）。

#### 2.4.2 场景渲染 (Scene Rendering)
*   **渲染器**: `services/management/IzakayaScene.ts`
*   **技术**: HTML5 Canvas 2D API。
*   **视觉效果**:
    *   **2.5D 伪 3D 效果**：墙壁和物体根据位置自动计算遮挡关系，支持“墙面厚度”绘制。
    *   **玻璃材质区分**：支持水平（Top）和垂直（Vertical）玻璃墙体的独立渲染逻辑，垂直玻璃墙拥有独特的框架和反光样式。
    *   **楼层交互**: 
        *   **楼梯触发**: 支持双向楼梯触发逻辑。
            *   **上楼 (Up)**: 撞击墙壁或走出楼梯区域时触发。
            *   **下楼 (Down)**: 走出楼梯区域（Walking Off）时触发，防止误触。
    *   **动态尺寸适配**：支持渲染任意尺寸的地图，自适应 Canvas 大小。

#### 2.4.3 经营状态 (Management State)
*   **数据结构**: 定义在 `gameStore.state.system.management`。
*   **核心指标**: `totalRevenue` (总营收), `customersServed` (客流量), `reputationGained` (声望), `difficulty` (难度)。
*   **状态机**: `isActive` (是否激活), `isTriggered` (是否触发事件)。

### 2.5 语音合成系统 (TTS System)

集成 **Genie-TTS** 提供的本地语音合成服务，为角色对话提供语音支持。

*   **架构**: Client-Server 模式。
    *   **Server**: 本地 Python FastAPI 服务。
    *   **Client**: 前端 `services/tts.ts`，负责播放队列管理。
*   **特性**:
    *   **角色绑定**: 支持为每个 NPC 绑定特定的参考音频 (Ref Audio) 和提示文本。
    *   **动态配置**: 在设置面板中可实时修改 TTS API 地址。

### 2.6 变量管理系统 (Variable System)

采用 **混合型数据结构 (Hybrid Structure)**，定义在 `src/types/game.ts`：

#### 2.6.1 玩家状态 (PlayerStatus)
*   **数值型**: `hp`, `max_hp`, `mp`, `max_mp`, `money`, `reputation` (声望)。
*   **文本型**: `location`, `time`, `date`, `clothing`, `identity`, `residence`。
*   **集合型**: `items` (物品), `spell_cards` (符卡), `authorities` (权限/头衔)。

#### 2.6.2 逻辑指令 (Logic Actions)
LLM #2 输出的 JSON 包含 `actions` 数组，支持以下操作：
1.  **UPDATE_PLAYER**: 修改玩家属性。
2.  **UPDATE_NPC**: 修改 NPC 属性。
3.  **INVENTORY**: 物品/符卡管理 (支持详细的符卡属性定义：伤害、范围、类型)。
4.  **SCENE**: 场景管理 (`location`, `add_chars`, `remove_chars`)。

---

## 3. UI/UX 设计规范 (UI Design)

采用 **三栏式响应布局**，强制 **浅色模式 (Light Mode)** 以配合和风纸质风格（亦提供深色模式选项）。

### 3.1 视觉风格 (Visual Style)
*   **Izakaya Paper**: 米纸纹理背景 + 木质边框 + 悬浮阴影。
*   **字体**: 使用衬线体增强文学感。
*   **动效**:
    *   **Smooth Streaming**: 模拟手写速度的流式输出。
    *   **Procedural Audio**: 配合文字生成的实时书写音效。

### 3.2 界面布局
*   **Left Sidebar (Status)**: 玩家状态卡片、物品栏、符卡栏、任务/约定列表。
*   **Center Stage (Dialogue)**: 对话气泡流 (Markdown + Image)、输入框。
*   **Right Sidebar (Environment)**: NPC 列表、**经营小地图/瓦片地图**。

---

## 4. 技术栈与目录结构 (Tech Stack & Structure)

### 4.1 技术栈
*   **Frontend**: Vue 3 + TypeScript + Vite
*   **State Management**: Pinia
*   **Styling**: Tailwind CSS v4
*   **Persistence**: Dexie.js (IndexedDB)
*   **LLM Client**: OpenAI SDK (Browser-compatible)
*   **Icons**: lucide-vue-next
*   **Markdown**: marked

### 4.2 关键目录结构 (`src/`)
*   **`services/`**: 核心业务逻辑
    *   `gameLoop.ts`: 游戏主循环，协调 LLM 调用。
    *   `logic.ts`: LLM #2 逻辑处理。
    *   `management/`: **经营系统相关**
        *   `MapGenerator.ts`: 地图生成与校验逻辑（含 Prompt）。
        *   `ZonePopulator.ts`: 地图填充与实例化逻辑。
        *   `IzakayaScene.ts`: 地图渲染与交互逻辑。
    *   `prompt.ts`: Prompt 构建。
    *   `audio.ts`: Web Audio API 音效。
*   **`stores/`**: Pinia 状态管理
    *   `game.ts`: 核心游戏状态 (Player, NPCs, System, Management)。
    *   `settings.ts`: 全局设置与 LLM 配置。
    *   `save.ts`: 存档管理。
*   **`components/`**: UI 组件
    *   `SettingsModal.vue`: 设置面板（含 LLM 配置、调试工具）。
    *   `management/`: 经营相关组件 (`IzakayaGame.vue`)。

---

## 5. 调试与开发工具 (Debug Tools)

内置于设置面板的调试工具，方便开发者快速验证功能：
*   **Prompt Debugger**: 查看当前构建的完整 Prompt 上下文。
*   **Management Mini Game Trigger**: 强制触发经营小游戏模式。
*   **Map Generator**: 输入提示词，实时生成并预览新的瓦片地图布局，支持“重新生成”以测试 Prompt 稳定性。

---

## 6. 待办事项 (Roadmap)

- [x] **基础架构**: Vue3 + Vite + Pinia + Dexie
- [x] **四重 LLM 架构**: Storyteller + Logic + Scribe + Misc
- [x] **核心游戏循环**: Turn-based + Snapshot
- [x] **变量与逻辑系统**: JSON Action Protocol
- [x] **任务与约定系统**: Quest & Promise Triggers
- [x] **战斗系统**: Turn-based + BGM + Talk (LLM #4)
- [x] **音效系统**: Procedural Writing Sound + BGM Manager
- [x] **UI 组件**: NewGameWizard, StatusPanel, ChatInterface
- [x] **TTS 系统**: Genie-TTS Integration (Local Service + Frontend)
- [x] **地图与经营系统**:
    - [x] LLM 驱动的瓦片地图生成 (MapGenerator)
    - [x] Canvas 2.5D 渲染 (IzakayaScene)
    - [x] 窗户与楼层支持
    - [x] **动态地图尺寸适配与连通性校验优化**
    - [x] **厨房布局算法优化 (Bar/Aisle Logic)**
    - [x] **楼梯交互系统优化**
- [x] **设置与存档**:
    - [x] 多存档管理 (SaveManager)
    - [x] 细粒度 LLM 配置 (LLMConfigPanel)
- [ ] **移动端适配**: 深度响应式布局优化
- [ ] **插画生成**: 集成 Stable Diffusion / DALL-E 进行场景/角色绘图
