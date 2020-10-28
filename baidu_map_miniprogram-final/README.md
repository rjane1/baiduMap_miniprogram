# Baidu-map-miniprogram

> Baidu-map-miniprogram

> 可实现功能：根据百度地图API获取用户位置经纬度信息；搜索、访达、标记地址并更新经纬度；规划小车经由用户以及目的地的最佳路线

## Build Setup

``` bash
# 运行项目准备工作
> 微信小程序：
  使用教程：https://gitchat.csdn.net/activity/5a93dd1719113f3d4bb9691d?utm_source=so
> 申请百度地图ak密钥：
  地址：http://lbsyun.baidu.com/index.php？title=%E9%A6%96%E9%A1%B5
  流程：注册 -> 登录 -> 控制台 ->创建应用，创建应用时，应用名称自定义，应用类型选择“微信小程序”，APPID为小程序的appId，然后提交。最终得到ak，将其粘贴至代码中相应位置即可。
> 更改接口ip：
  pages/map/map.js line438 
  url:'http://server.natappfree.cc:33150/ocean/get_closet_ugv_id' 更改ip数字
  


```

## 接口
函数位置于/pages/map/map.js

## 逆地址解析
函数位置于/pages/map/map.js

