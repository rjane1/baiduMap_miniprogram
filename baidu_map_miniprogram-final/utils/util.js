const formatTime = date => {
  const year = date.getFullYear()
  const month = date.getMonth() + 1
  const day = date.getDate()
  const hour = date.getHours()
  const minute = date.getMinutes()
  const second = date.getSeconds()

  return [year, month, day].map(formatNumber).join('/') + ' ' + [hour, minute, second].map(formatNumber).join(':')
}

const formatNumber = n => {
  n = n.toString()
  return n[1] ? n : '0' + n
}

/**
 *  判断经纬度是否超出中国境内
 */
function isLocationOutOfChina(latitude, longitude) {
  if (longitude < 72.004 || longitude > 137.8347 || latitude < 0.8293 || latitude > 55.8271)
    return true;
  return false;
}

/**
 *  将GCJ-02(火星坐标)转为百度坐标:
 */
function transformFromGCJToBaidu(latitude, longitude) {
  var pi = 3.14159265358979324 * 3000.0 / 180.0;

  var z = Math.sqrt(longitude * longitude + latitude * latitude) + 0.00002 * Math.sin(latitude * pi);
  var theta = Math.atan2(latitude, longitude) + 0.000003 * Math.cos(longitude * pi);
  var a_latitude = (z * Math.sin(theta) + 0.006);
  var a_longitude = (z * Math.cos(theta) + 0.0065);

  return {
    latitude: a_latitude,
    longitude: a_longitude
  };
}

module.exports = {
  formatTime: formatTime,
  isLocationOutOfChina: isLocationOutOfChina,
  transformFromGCJToBaidu: transformFromGCJToBaidu,
}