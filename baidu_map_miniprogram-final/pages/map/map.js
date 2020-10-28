
// pages/map/map.js
const app = getApp();
// 引用百度地图微信小程序JSAPI模块
const BMap = require('../../libs/bmap-wx.min.js');
var bmap;
var util = require('../../utils/util.js');
const pinIcon = '../../public/image/lushu.png';
const poiIcon = '../../public/image/location.png';
const sltIcon = '../../public/image/location-selected.png';
Page({
  mapCtx: undefined,
  /**
   * 页面的初始数据
   */
  data: {
    result: [],
    searchCon:'',     //输入内容
    searchResult:[],  //搜索列表
    searchTick: 0,
    
    // 这两个属性用于定位地图中心，修改时会触发regionchange
    // 但是regionchange的时候不会刷新这两个量，否则将导致循环调用
    longitude: '', 
    latitude: '',

    // 中心坐标 实时刷新
    center: { longitude: '', latitude: '', },

    // 当前位置 定时刷新
    current: { longitude: '', latitude: '', },
    address: '',

    // 控制选点标签
    lockPicker: false,
    showPicker: false,
    initial: true,

    // 当前被选中的markerId
    selectedMarkerId: -1,

    path_longitude: '',
    path_latitude:'',

    scale: 13, //地图的扩大倍数
    des_lat: '',//目的地纬度
    des_lng: '',//目的地经度
    user_path:[],
    car_num:'',

    // 这两个数组对象由腾讯地图API原生支持
    polyline: [],
    markers: [
      {
        id: 1,
        latitude: '',
        longitude: '',
        iconPath: poiIcon,
        width: 30,
        height: 30,
      },
    ],
    carLocation:[{
      "id": 1,
      "lat":"121.449043",
      "lng": "31.031268",
      "desc":"电信群楼5号楼东侧路边(环一路)",
      "name": "car_1"
    },{
      "id": 2,
      "lat":"121.447176",
      "lng": "31.033731",
      "desc":"新行政楼",
      "name": "car_2"
    },{
      "id": 3,
      "lat":"121.444233",
      "lng": "31.031201",
      "desc":"研究生院",
      "name": "car_3"
    },{
      "id": 4,
      "lat":"121.452375",
      "lng": "31.03736",
       "desc":"船舶海洋与建筑工程学院",
      "name": "car_4"
    },{
       "id": 5,
       "lat":"121.437649",
        "lng": "31.024924",
        "desc":"思源门行政楼",
        "name": "car_4"
    }]


  },

  /**
   * 生命周期函数--监听页面加载
   */
  onLoad:function(options) {

    // 实例化百度地图API核心类
    bmap = new BMap.BMapWX({
      ak: app.globalData.ak
    });
    
    //获取当前位置经纬度
    const that = this;
    wx.getLocation({
      type: 'gcj02',
      success: (res) => {
        console.log('Current Location: ', res);
        that.setData({
          longitude: res.longitude,
          latitude: res.latitude,
          current: res,
          center: res,
        });
      }
    })

    // 创建地图上下文
    this.mapCtx = wx.createMapContext("myMap");
    this.updateCenter(
      (center) => this.regeocoding(center, 
        (address) => this.setData({ address: address }))
    );
    
  },

  // 绑定input输入 --搜索
  bindKeyInput(e){
    if (e.detail.value == "") {
      this.setData({searchResult: []});
      return;
    }
    // 节流 防止触发百度接口并发限制
    var currentTick = new Date().getTime();
    if (currentTick - this.data.searchTick < 500)
      return;
    this.setData({
      searchTick: currentTick
    });

    var that = this;
    var fail = function (data) { //请求失败
      console.log(data) 
    };
    var success = function (data) { //请求成功
      var searchResult =[];
      for(var i=0;i<data.result.length;i++){ //搜索列表只显示10条
        if(i>10){ 
          return;
        }
        if (data.result[i].location){
          data.result[i]['id'] = i;
          searchResult.push(data.result[i]);
        }
      }
      that.setData({
        searchResult: searchResult
      });
    }

    // 发起suggestion检索请求 --模糊查询
    bmap.suggestion({
      query: e.detail.value,
      city_limit: false,
      fail: fail,
      success: success
    });
  },

  // 使用回车时 
  showAll() {
    this.setData({
      markers: this.data.searchResult.map(
        (res) => { return { 
          id: res.id,
          title: res.name,
          latitude: res.location.lat,
          longitude: res.location.lng,
          iconPath: poiIcon,
          width: 30,
          height: 30,
          address: res.province + res.address
        }
      }),
      searchResult: [],
      lockPicker: false,
      showPicker: false,
    })
  },

  // 点击搜索列表某一项
  tapSearchResult(e){
    var that = this;
    var value = e.currentTarget.dataset.value;
    let markers = [{ 
      id: 0,
      title: value.name,
      latitude: value.location.lat,
      longitude: value.location.lng,
      iconPath: sltIcon,
      width: 30,
      height: 30,
      address: value.province + value.address,
    }]

    this.mapCtx.moveToLocation({
      longitude: value.location.lng,
      latitude: value.location.lat,
      success: (res) => {}
    })

    that.setData({
      lockPicker: false,
      showPicker: false,
      markers: markers,
      selectedMarkerId: 0,
      searchResult: []
    })
  },
  
 
  // 这个方法没用
  // getLngLat: function() {
  //   var that = this;
  //   this.mapCtx = wx.createMapContext("myMap");
  //   var latitude, longitude;
  //   this.mapCtx.getCenterLocation({
  //     success: function(res) {
  //       latitude = res.latitude;
  //       longitude = res.longitude;
  //       var str = 'markers[0].longitude',
  //         str2 = 'markers[0].latitude';
  //       var array = [];
  //       /**
  //        * 将GCJ-02(火星坐标)转为百度坐标
  //        */
  //       var result2 = util.transformFromGCJToBaidu(res.longitude, res.latitude);
  //       console.log("Center location: ", result2)
  //       array.push(result2);
  //       that.setData({
  //         longitude: res.longitude,
  //         latitude: res.latitude,
  //         [str]: res.longitude,
  //         [str2]: res.latitude,
  //         result: array,
  //       })
  //       //that.regeocoding();
  //     }
  //   })

  //   //平移marker，修改坐标位置 
  //    this.mapCtx.translateMarker({
  //      markerId: 1,
  //      autoRotate: true,
  //      duration: 1000,
  //      destination: {
  //        latitude: latitude,
  //        longitude: longitude,
  //      },
  //      animationEnd() {
  //        console.log('animation end')
  //      }
  //    })
  // },

  //地图位置发生变化
  regionchange(e) {
    // 地图发生变化的时候，获取中间点，也就是用户选择的位置
    let detail = e.detail;
    console.log(e.detail)
    this.updateCenter();
    if ((detail.causedBy == 'gesture' || 'gesture' in detail) && !this.data.lockPicker)
      this.setData({ showPicker: true });
    if (detail.type == 'end' && !this.data.lockPicker)
      this.regeocoding(this.data.center, (address) => this.setData({ address: address}));
  },
  
  updateCenter: function(func) {
    this.mapCtx.getCenterLocation({
      success: (res) => { 
        this.setData({
          center: res
        });
        if (!(typeof func == 'undefined'))
          func(res);
      },
      fail: (res) => { console.warn(res) },
      complete: () => { console.log()}
    });
    this.setData({ initial: false });
  },

  regeocoding: function(location, func) {
    bmap.regeocoding({
      success: (res) => func(res.wxMarkerData[0].address),
      fail: (res) => { console.log('regeocoding failed: ', res.message) },
      location: location.latitude + ',' + location.longitude
    });
  },

  markertap(e) {
    console.log("Tap marker: ", e.detail.markerId)
    if (this.data.selectedMarkerId == e.detail.markerId)
      this.setData({ 
        ['markers['+ e.detail.markerId +'].iconPath']: poiIcon,
        selectedMarkerId: -1
      });
    if (this.data.selectedMarkerId == -1)
      this.setData({ 
        ['markers['+ e.detail.markerId +'].iconPath']: sltIcon,
        selectedMarkerId: e.detail.markerId
      });
    else
      this.setData({ 
        ['markers['+ e.detail.markerId +'].iconPath']: sltIcon,
        ['markers['+ this.data.selectedMarkerId +'].iconPath']: poiIcon,
        selectedMarkerId: e.detail.markerId
      });
  },

  // 调用该方法来显示路线并执行动画（当doAnimation为true）
  showPath: function(points, doAnimation) {
    this.setData({
      polyline: [{
        points: points,
        color:"#1E90FFBF",
        width: 6,
        dottedLine: false
      }]
    })

    if (doAnimation) {
      let markers = this.data.markers;
      if(!markers.some((marker) => marker.id == -1))
        markers.push({ 
          id: -1,
          latitude: points[0].latitude,
          longitude: points[0].longitude,
          iconPath: pinIcon,
          anchor: {x:.5, y:.5}, 
          width: 20,
          height: 20,
        })
      this.setData({ markers: markers });
      this.mapCtx.moveAlong({
        markerId: -1,
        path: points,
        duration: 3000,
        success: (res) => { console.log()},
      })
    }
  },

  controltap(e) {
    var that = this;
    console.log("scale===" + this.data.scale)
    if (e.controlId === 1) {
      that.setData({
        scale: ++this.data.scale
      })
    } else {
      that.setData({
        scale: --this.data.scale
      })
    }
  },

  click: function() {
    this.getLngLat()
  },

  //提示
  // tipsModal: function (msg) {
  //   wx.showModal({
  //     title: '提示',
  //     content: msg,
  //     showCancel: false,
  //     confirmColor: '#2FB385'
  //   })
  // },

  downloadFile: function () {
    wx.downloadFile({
      url: 'http://yqxspj.natappfree.cc/ocean/download',
      success(res) {
        console.log(res)
        // 只要服务器有响应数据，就会把响应内容写入文件并进入 success 回调，业务需要自行判断是否下载到了想要的内容
        if (res.statusCode === 200) {
          wx.saveFile({
            tempFilePath: res.tempFilePath,
            success: function (res) {
              console.log(res)
              var savedFilePath = res.savedFilePath
              console.log("文件已下载到：" + savedFilePath)
              wx.getSavedFileList({
                success: function (res) {
                  console.log(res)
                }
              })
              wx.openDocument({
                filePath: savedFilePath,
                success: function (res) {
                  console.log('打开文档成功')
                }
              })
            }
          })
          // wx.playVoice({
          //   filePath: res.tempFilePath
          // })
        }
      },
      fail: function (res) {
        console.log(res)
      }
    })
  },
  

  //接口数据库函数：
  sendData: function(){
    const that = this;
    var tmp = [];

    let start = util.transformFromGCJToBaidu(this.data.current.latitude,this.data.current.longitude);
    //let start = this.data.current;
    
    let des = util.transformFromGCJToBaidu(this.data.markers[this.data.selectedMarkerId].latitude, this.data.markers[this.data.selectedMarkerId].longitude);
    //let des = this.data.markers[this.data.selectedMarkerId];

    wx.request({
      // 发送当前经纬度信息
      url:'http://server.natappfree.cc:33150/ocean/get_closet_ugv_id', 
      header: { 'content-type': 'application/json' },
      data: {
        //data部分目的地经纬度信息需要用户搜索目的地，点击后屏幕出现绿点标记，而后点击规划路线
        //gcj:'1',
        start_lat: start.latitude,
        start_lng: start.longitude,
        //mid_lat: (parseFloat(start.latitude)+parseFloat(des.latitude))/2,
        //mid_lng: (parseFloat(start.longitude)+parseFloat(des.longitude))/2,
        mid_lat: (start.latitude + des.latitude)/2,
        mid_lng: (start.longitude + des.longitude)/2,
        des_lat: des.latitude,
        des_lng: des.longitude
      },
      method: 'get',
      success: function (res) {
        if (res.statusCode != 200) {
          console.warn("Route query failed")
          return;
        }
        console.log("Route query: ", res);
        that.setData({
            car_num: res.data.car_num,
            distance: res.data.distance,
            arrived_time: res.data.arrived_time,
            car_lat: res.data.car_lat,
            car_lng: res.data.car_lng,
            user_path: res.data.user_path_gcj.map((p) => {
              return {
                longitude: p.lng,
                latitude: p.lat
              }
            })
        })
        that.showPath(that.data.user_path, true);
      },
    })
    
  },  
  
  /**
   * 生命周期函数--监听页面初次渲染完成
   */
  onReady: function() {

  },

  /**
   * 生命周期函数--监听页面显示
   */
  onShow: function() {

  },

  /**
   * 生命周期函数--监听页面隐藏
   */
  onHide: function() {

  },

  /**
   * 生命周期函数--监听页面卸载
   */
  onUnload: function() {

  },

  /**
   * 页面相关事件处理函数--监听用户下拉动作
   */
  onPullDownRefresh: function() {

  },

  /**
   * 页面上拉触底事件的处理函数
   */
  onReachBottom: function() {

  },

  /**
   * 用户点击右上角分享
   */
  onShareAppMessage: function() {

  }
})