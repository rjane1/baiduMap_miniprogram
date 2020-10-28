// pages/button/button.js
Page({

  /**
   * 页面的初始数据
   */
  data: { 
    dataList:[]
  },

  /**
   * 生命周期函数--监听页面加载
   */
  onLoad: function (options) {
    var th = this;
    wx.request({
      data:{},
      url:'http://192.168.1.107:8484/ocean/all',
      method:'GET',
      header:{
        'content-type':'application/json'
      },
      success: function(res){
        console.log(res.data);
        th.setData({
          dataList:res.data
        })
        console.log(12235)
      },
      fail: function(res){
        console.log("---------fail")
      }
    });
    wx.request({
      url:'',
      method:"POST",
      data:{
        id:data
      },
      header:{
        'content-type':'application/x-www-form-urlencode'
      },
      success:function(res){
        th.setData({

        });
        console.log(hfhsfvc)
      },
      fail:function(res){
        console.log(98645)
      }
    })
  },

  /**
   * 生命周期函数--监听页面初次渲染完成
   */
  onReady: function () {

  },

  /**
   * 生命周期函数--监听页面显示
   */
  onShow: function () {

  },

  /**
   * 生命周期函数--监听页面隐藏
   */
  onHide: function () {

  },

  /**
   * 生命周期函数--监听页面卸载
   */
  onUnload: function () {

  },

  /**
   * 页面相关事件处理函数--监听用户下拉动作
   */
  onPullDownRefresh: function () {

  },

  /**
   * 页面上拉触底事件的处理函数
   */
  onReachBottom: function () {

  },

  /**
   * 用户点击右上角分享
   */
  onShareAppMessage: function () {

  }
})