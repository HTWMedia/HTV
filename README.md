# HTV
A live media player app（手机、电视直播软件）

app可在右侧release中下载，免费使用，如需定自定义源可联系作者。

![image](https://img2024.cnblogs.com/blog/33211/202405/33211-20240505115550874-1758625402.png)

## 使用

Android系统的手机或电视上

### 1.电视操作
+ 频道切换：使用上下方向键，或者数字键切换频道；屏幕上下滑动；
+ 频道选择：OK键；单击屏幕；
+ 设置页面：菜单、帮助键、长按OK键；双击屏幕

### 2.手机操作
+ 频道切换：屏幕上下滑动；
+ 频道选择：单击屏幕；
+ 设置页面：双击屏幕

## 说明

+ 支持Android较低的版本，如Android 4.4等
+ 网络环境IPv4或IPv6均可
+ 直播源稳定，初始化为央视、卫视及当地地方台。
+ 节目信息epg采用异步加载，可能稍有延迟

## 声明

由于为了兼容IPTV4网络和比较老的Android系统，HTV app采用了开源的Fijkplayer播放器，导致在进入app和切换台的时候可能延迟比较大，这块由于本人精力有限，目前没有好的解决方案，有这方面best practice的同仁可以指导下，在此感谢。

为了解决上述问题，考虑将获取tv频道的API释放出来，以便于您能用其它播放器。目前主要有4个API：

+ **获取频道列表**
<details open>
<summary>点击查看代码</summary>

```
http://8.136.199.131/Home/GetIPTVs

返回频道列表的json字符串，例如：[{"title":"CCTV1 HD","url":"http://61.48.189.27:1314/rtp/239.3.1.129:8008","logo":"","grouptitle":"央视","groupidx":0},{"title":"CCTV2 HD","url":"http://61.48.189.27:1314/rtp/239.3.1.60:8084","logo":"","grouptitle":"央视","groupidx":0}]

上述title是频道名，url是频道源，grouptitle是分组，比如央视、卫视等
```
</details>

+ **根据地区获取频道列表**
<details open>
<summary>点击查看代码</summary>

```
http://8.136.199.131/Home/GetIPTVsByLoc?location=
返回频道列表的json字符串

location参数可以传入比如location=湖北省，这时候严格返回该地区的频道，包括央视、卫视和地方频道。
如果没有的话可以放开一些，比如只传入location=湖北，这时候会返回和湖北地区相关的频道。

根据地区获取频道列表比直接获取频道列表快，因为少了检索地区的时间。
```
</details>

+ **检测某个频道是否可用**
<details open>
<summary>点击查看代码</summary>

```
http://8.136.199.131/Home/ProbeChannel?url=

返回频道是否可用以及频道响应时间的json字符串

url传入比如url=http://61.48.189.27:1314/rtp/239.3.1.129:8008
```
</details>

+ **根据频道名称检索频道源url**
<details open>
<summary>点击查看代码</summary>

```
http://8.136.199.131/Home/GetIPTV?s=

返回频道url

s传入比如s=cctv3等，cctv3是频道频道名称
```
</details>

**以上接口获取的源均为稳定的IPv4源，会自动更新，节省您宝贵的时间，调用后不用更新app**

另外获取epg节目信息的方法，可参考网上资源。上述API可在浏览器中直接访问即可有返回值查看，方便作为自定义源，在其它app中使用。

开发创作不易，如果您觉得有用或者节省了您宝贵的时间，请给作者小小赞下吧，3Q：
<p>
<img src="https://img2024.cnblogs.com/blog/33211/202405/33211-20240511115250248-1117416631.jpg" style="width: 300px; height: 300px;"/>
<img src="https://img2024.cnblogs.com/blog/33211/202405/33211-20240511115429872-844027794.jpg" style="width: 300px; height: 300px;"/>
</p>

## 另有以下API：
* 堪比capcut(剪映）的智能字幕
* 人声背景音乐分离
* 图文成片(根据文案搜索图片背景音乐及短视频等素材合成视频)
* 音视频说话人区分
* 提取音视频重点内容
* 音视频内容总结
* 视频字幕OCR提取
* 图片、文档OCR识别，包含复杂表格识别、试卷识别、公式识别、PDF识别等

如有以上需求的同仁可联系作者

## 致谢
[my_tv](https://github.com/yaoxieyoulei/my_tv "my_tv")
