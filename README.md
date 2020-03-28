# TTPatch
热修复、热更新、JS代码动态下发、动态创建类


[1. 使用文档](https://github.com/yangyangFeng/TTPatch/blob/master/%E4%BD%BF%E7%94%A8%E6%96%87%E6%A1%A3.md)

[2. 基础用法](https://github.com/yangyangFeng/TTPatch/wiki/%E5%9F%BA%E7%A1%80%E7%94%A8%E6%B3%95)






## 1. 功能列表

|功能特性|备注限制|
|-|-|
|**替换指定`ObjectC`方法实现**          | 实例/静态方法均可替换实现|
|**支持`block`**                      |`ObjectC`传入`JS`,  `JS`传入`ObjectC`均已支持|
|**支持添加属性**                     |为已存在的`class`添加属性|
|**支持基础数据类型**                   |非id类型,如`int`,`bool`均已支持|
|**支持下发纯`JS`页面**                    |纯`JS`代码映射原生代码,动态发布|

---------------------------------------------------

**演示项目**:Example.xcodeproj 

![效果图.gif](http://code.cocoachina.com/uploads/attachments/20191030/1000267/1ef16348536be6c1a901ced275d8d387.gif)


![taobao.gif](https://imgconvert.csdnimg.cn/aHR0cHM6Ly91cGxvYWQtaW1hZ2VzLmppYW5zaHUuaW8vdXBsb2FkX2ltYWdlcy8xMjQ5MzI5LTVlZjA2MGU1MjBlZDFkZTguZ2lm)

## 2. 安装


### CocoaPods

1. 在 Podfile 中添加  `pod 'TTPatch'`。
2. 执行 `pod install` 或 `pod update`。
3. 导入 "TTPatch.h"

