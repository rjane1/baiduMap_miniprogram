require 'mavlink/index'
require 'modbus/modbus'
require 'spreadsheet'
require 'socket'
require 'csv'
require 'sqlite3'
require 'rubygems'
require 'spreadsheet/excel'
require 'fastercsv'
require 'coordconver'
require 'mongo'
require 'mathn'
require 'lograge'
require 'open-uri'
require 'kafka'
require 'mqtt'

# -*- coding: gbk -*-

class OceanController < ApplicationController
  # SERVER：socket通信ip，PORT：socket通信的端口
  # M_SERVER：连接mongodb的ip，PORT：连接mongodb的端口
  # SERVER = 'localhost'
  # M_SERVER = 'localhost'
  M_SERVER = '192.168.1.156'
  SERVER = '192.168.1.156'
  PORT = 8888
  M_PORT = 27017

  def all
    # self.class.mqttsend '/sensor/control/1', self.class.sensor_request
    data = Ocean.information
    render json: data, callback: params['callback']
  end

  def information
    ocean = Ocean.first
    data = {:speed => ocean.speed,
            :angle => ocean.angle,
            :communicate => ocean.communicate,
            :time => ocean.time,
            :battery => ocean.battery,
            :radius => ocean.radius,
            :lng => PlanStatus.first.lng,
            :lat => PlanStatus.first.lat}
    render json: data, callback: params['callback']
  end

  # tcp通信方法，与小车的 tcp 连接
  def tcp_socket
    socket = TCPSocket.open(SERVER, PORT)
    return socket
  end

#无人船部分

  def four_arguments
    self.class.mqttsend '/sensor/control/1', self.class.sensor_request
    plan = PlanStatus.first
    data = {:ph => plan.ph,
            :conductivity => plan.conductivity,
            :turbidity => plan.turbidity,
            :oxygen => plan.oxygen,
            :temperature => plan.temperature,
            :voltage1 => plan.voltage1,
            :voltage2 => plan.voltage2,
            :lng => plan.lng,
            :lat => plan.lat}
    render json: data, callback: params['callback']
  end

  def water_mobile
    plan = PlanStatus.first
    data = {:ph => plan.ph,
            :conductivity => plan.conductivity,
            :turbidity => plan.turbidity,
            :oxygen => plan.oxygen,
            :temperature => plan.temperature,
            :voltage1 => plan.voltage1,
            :voltage2 => plan.voltage2,
            :lng => plan.lng,
            :lat => plan.lat}
    render json: data
  end

  # 移动端获取六参数接口（暂时只有3个是来自真实数据源）
  def info_mobile
    ocean = Ocean.first
    data = {:speed => ocean.speed,
            :angle => ocean.angle,
            :communicate => ocean.communicate,
            :time => ocean.time,
            :battery => ocean.battery,
            :radius => ocean.radius}
    render json: data
  end

  # 根据移动端语音输入处理结果设置无人船工作模式
  # 4：停止
  # 10：开始
  # 11：返航
  # 15：绕开
  # 20：反推
  def mode
    new_mode = params['mode'].to_i
    if [4,10,11,15,20].include?(new_mode)
      if new_mode == 11 #处理返航模式，设置返航点
        position = Route.first
        if position != nil
          self.class.mqttget_routes(1, [position.lng], [position.lat])
        end
      elsif new_mode == 15 #处理绕开模式，自动生成一个路径点
        position = Route.last
        if position != nil
          Route.create(:lng => position.lng + 0.001, :lat => position.lat + 0.0005)
          self.class.mqttget_routes(1, [position.lng + 0.001], [position.lat + 0.0005])
        end
      else
        self.class.mqttsend '/usv/control/1', self.class.send_command_long_arm
      end
      self.class.mqttsend '/usv/control/1', self.class.send_set_mode(new_mode)
      render json: {:status => 'ok'}
    else
      render json: {:status => 'wrong'}
    end
  end

  #get the real-time loc的副ation of the car, update the sql
  def get_realtime_loc
    rev_num = params['id']
    rev_lat = params['lat'].to_f
    rev_lng = params['lng'].to_f
    plan = PlanStatus.first
    plan.lat = rev_lat
    plan.lng = rev_lng
    plan.save      #save to the sql
    render json:{:status => 'ok'}
  end

  #send alarm message
  def send_message
    rev_lat = params['lat']
    rev_lng = params['lng']
    code = rev_lat+","+rev_lng
    client = RPCClient.new(
        access_key_id:     '<accessKeyId>',
        access_key_secret: '<accessSecret>',
        endpoint: 'https://dysmsapi.aliyuncs.com',
        api_version: '2017-05-25'
    )

    response = client.request(
        action: 'SendSms',
        params: {
            RegionId: "cn-hangzhou",
            PhoneNumbers: "18217260862",
            SignName: "Unmanned Car",
            TemplateCode: "您的小车在${code}发生故障",
            TemplateParam: code
        },
        opts: {
            method: 'POST'
        }
    )

    render json:{:status => response}
  end

  

### 无人车部分
##文件管理功能

  # 路径处理转换方法，设备格式经纬度，gps => gcj02 =>bd09
  def gps_bd09(lat, lng)
    # 由于传入的可能是字符串型的经纬度，保险起见转换一下
    # 设备格式转bd09格式，例22xx.xxxx, 121yy.yyyy
    # bd09格式 = 22 + xx.xxxx/60, 121 + yy.yyyy/60
    a_lat = lat.to_i.div(100) + lat.to_f%100/60
    a_lng = lng.to_i.div(100) + lng.to_f%100/60
    
    # wgs先转gcj再转bd09会更精确一点
    temp = Coordconver.wgs_gcj(a_lng, a_lat)
    a = Coordconver.gcj_bd(temp[0], temp[1])
    # 返回纬度，经度
    return a[1], a[0]
  end

  # 路径转换方法，wgs => gcj02 => bd09
  def wgs_bd09(lat, lng)
    temp0 = Coordconver.wgs_gcj(lng, lat)
    temp1 = Coordconver.gcj_bd(temp0[0], temp0[1])
    # 返回纬度，经度
    return temp1[1], temp1[0]
  end

  # 逆路径转换方法，bd09 => gcj02 => wgs
  def bd09_wgs(lat, lng)
    temp0 = Coordconver.bd_gcj(lng, lat)
    temp1 = Coordconver.gcj_wgs(temp0[0], temp0[1])
    # 返回纬度、经度
    return temp1[1], temp1[0]
  end

  # 同步文件方法，同步 equipment_csv 到 bd09_csv 文件夹
  # equipment_csv下 下发给小车     bd09_csv下  发送给前端
  def w_bd09
    # 保障 bd09 文件夹不会有多余的内容
    if File.directory?"#{Rails.root}/bd09_csv"
      FileUtils.rm_r("#{Rails.root}/bd09_csv")
      Dir.mkdir("#{Rails.root}/bd09_csv")
    end
    # 遍历 equipment_csv 内文件，同步到bd09_csv内
    Dir.foreach("#{Rails.root}/equipment_csv") do |filename|
      if filename != '.' && filename != '..'
        content = CSV.read("#{Rails.root}/equipment_csv/#{filename}")
        content = JSON.parse(content.to_json)

        CSV.open("#{Rails.root}/bd09_csv/#{filename}", "wb") do |arr|
          arr << ["id", "lat", "lng"]
          for i in 1..content.length-1
            # 根据 121+26.xxx/60 计算
            lat = content[i][1].to_i.div(100) + (content[i][1].to_f % 100)/60
            lng = content[i][2].to_i.div(100) + (content[i][2].to_f % 100)/60
            
            temp = Coordconver.wgs_gcj(lng, lat)
            a = Coordconver.gcj_bd(temp[0], temp[1])
            arr << [content[i][0], a[1], a[0]]
          end
        end
      end
    end
  end

  # 最新文件方法，保持latest.csv 内容为最新文件的内容
  def update_latest
    file_list = []
    Dir.foreach("#{Rails.root}/equipment_csv") do |filename|
      # 去除非时间命名格式文件
      if filename != '.' && filename != '..' && filename != 'test1015-2.csv' && filename != 'planned_path.csv' && filename != 'back.csv'
        file_list.push(filename)
      end
    end
    # 文件名排序
    l_file = file_list.sort
    # 读取列表最后一个文件
    content = CSV.read("#{Rails.root}/equipment_csv/#{l_file[-1]}")
    content = JSON.parse(content.to_json)

    CSV.open("#{Rails.root}/latest/latest.csv", "wb") do |arr|
      arr << ["id", "lat", "lng"]
      for i in 1..content.length-1
        # 根据 121+26.xxx/60 计算
        lat = content[i][1].to_i.div(100) + (content[i][1].to_f % 100)/60
        lng = content[i][2].to_i.div(100) + (content[i][2].to_f % 100)/60

        temp = Coordconver.wgs_gcj(lng, lat)
        a = Coordconver.gcj_bd(temp[0], temp[1])
        arr << [content[i][0], a[1], a[0]]
      end
    end
  end

  # 读写文件方法，传入需要读取的文件名写入equiment_csv下 同名文件
  def manage_point(filename)

    # 读取 csv 文件内容
    content = CSV.read("#{Rails.root}/#{filename}")
    time = Time.new
    f_time = time.strftime("%Y_%m_%d_%H_%M")

    CSV.open("#{Rails.root}/equipment_csv/#{f_time}_P#{content.length-1}.csv","wb") do |arr|
      
      for i in 0..content.length-1
        arr << content[i]
      end
    end
  end

  # 历史记录方法，更新csv调用的历史
  def csv_history
    time = Time.new
    f_time = time.strftime("%Y-%m-%d %H:%M:%S")

    # 获取文件列表
    file_list = []
    Dir.foreach("#{Rails.root}/equipment_csv") do |filename|
      if filename != '.' && filename != '..' && filename != 'test1015-2.csv'
        file_list.push(filename)
      end
    end
    # 文件名排序
    l_file = file_list.sort

    # 判断历史文件存在？
    if File::exists?("#{Rails.root}/history.csv")
      # 读取文件列表
      content = CSV.read("#{Rails.root}/history.csv")
      # 去除一样的文件
      file_name = l_file[content.length-1..l_file.length]
      # 连接上一个id
      arr=CSV.read("#{Rails.root}/history.csv")
      id = arr[arr.length-1,arr.length]           
      i=id[0][0].to_i
      CSV.open("#{Rails.root}/history.csv","a") do |csv|
        for j in 0..file_name.length-1
          puts file_name[j]
          csv << [i + 1, file_name[j], f_time]
        end    
      end
    else
      File.new("#{Rails.root}/history.csv","w")
      CSV.open("#{Rails.root}/history.csv","a") do |csv|
        csv << ['id', 'name', 'sys_time']
        for i in 0..l_file.length-1
          csv << [i + 1, l_file[i], f_time]
        end  
      end
    end
  end

  # 生成日志方法，日志文件的生成
  def create_my_logger(file_name)
    logger = Logger.new("#{Rails.root}/log/#{file_name}")
    logger.level = Logger::DEBUG
    logger.formatter = proc do |severity, datetime, progname, message|
      "[#{datetime.to_s(:db)}] [#{severity}] #{message}\n"
    end
    logger
  end

  # 生成word文档
  def word_doc
    data = JSON.parse(Ocean.all.to_json)
    data_plan = JSON.parse(PlanStatus.all.to_json)
    time = Time.new
    f_time = time.strftime("%Y-%m-%d-%H-%M")
    Caracal::Document.save 'example.docx' do |docx|
      docx.h3 f_time
      docx.p 'speed: ' + data.first['speed'].to_s
      docx.p 'angle: ' + data.first['angle'].to_s
      docx.p 'battery: ' + data.first['battery'].to_s
      docx.p 'radius: ' + data.first['radius'].to_s
      docx.p 'lat: ' + data_plan.first['lat'].to_s
      docx.p 'lng: ' + data_plan.first['lng'].to_s
    end
    render json: {:status => "ok"}
  end

  # 小车下载文件接口
  def download
    send_file "test.csv"
    # send_file "1026-1.xls"
    #send_file "public/files/"+params[:filename] unless params[:filename].blank?
  end

  # 接受小车传递的各类传感器信息，写入文件内
  def receive_parameter
    parameter = params['url']
    aFile = File.new("parameter.txt", "wb")
    aFile.syswrite(parameter)
    render json: {:status => "ok"}
  end
  

##用户流程
  #连接mongodb，只连接一个
  def connet_mongdb1 
    #连接mongodb，只连接一个
    client = Mongo::Client.new("mongodb://#{M_SERVER}:#{M_PORT}/ugv")
    db = client.database #获取数据库
    return db
  end

  # osm
  # 转换路网文件方法，转换python脚本生成的路网文件，格式转为bd09
  def trans_plan
    # 读取脚本生成的路网文件
    plan_wgs = CSV.read("#{Rails.root}/planned_path.csv")
    plan_wgs = JSON.parse(plan_wgs.to_json)
    
    # 打开bd09格式路网文件并写入
    CSV.open("#{Rails.root}/bd09_csv/planned_path.csv", "wb") do |arr|
  
      arr << ["id", "lat", "lng"]
      for i in 1..plan_wgs.length-1
        # 调用路径转换方法
        plan_bd = wgs_bd09(plan_wgs[i][1].to_f, plan_wgs[i][2].to_f)
        arr << [plan_wgs[i][0], plan_bd[0], plan_bd[1]]
      end
    end
    
    # 打开设备格式路网文件并写入
    CSV.open("#{Rails.root}/equipment_csv/planned_path.csv", "wb") do |csv|
      csv << ["id", "lat", "lng"]
      for i in 1..plan_wgs.length-1
        lat = plan_wgs[i][1].to_f
        lng = plan_wgs[i][2].to_f
        lat_em = lat.div(1) * 100 + lat % 1 * 60
        lng_em = lng.div(1) * 100 + lng % 1 * 60
        csv << [i-1, lat_em, lng_em]
      end
    end
  end

  # midmaplat, midmaplng, olat, olng, dlat, dlng
  # 地图中点、起点、终点
  def osm_plan(*args)
    # 接收bd09格式的经纬度
    #参数  olat, olng, dlat, dlng,midmaplat, midmaplng,

    # midmaplat=22.677003
    # midmaplng=113.844444
    # olat=2240.415618
    # olng=11350.006345
    # olat, olng=gps_bd09(olat, olng)
    # dlat=22.675902
    # dlng=113.844482
    
    # 电院4号楼
    # midmaplat = 31.030653
    # midmaplng = 121.448205
    # olat = 31.030858
    # olng =121.447779
    # dlat = 31.030672
    # dlng = 121.448757
 
    # olat = 31.030324
    # olng =121.448646
    # dlat = 31.030858
    # dlng = 121.447779
    olat = args[0].to_f
    olng = args[1].to_f
    dlat = args[2].to_f
    dlng = args[3].to_f
    midmaplat = args[4].to_f
    midmaplng = args[5].to_f

    mid_temp = bd09_wgs(midmaplat, midmaplng)
    o_temp = bd09_wgs(olat, olng)
    d_temp = bd09_wgs(dlat, dlng)
    puts mid_temp[0].to_s
    puts o_temp[0]
    puts d_temp[0]    
    
    # 调用系统终端输入
    system "python3 " << Rails.root.to_s << "/planned_path/osmnx_test.py -m " << mid_temp[0].to_s << " -n " << mid_temp[1].to_s << " -o " << o_temp[0].to_s << " -p " << o_temp[1].to_s << " -d " << d_temp[0].to_s << " -e " << d_temp[1].to_s
  
   # 调用转换路网文件方法
   trans_plan
  end

  # 返回计划路径内容给前端
  def planned_path
  
    # osm_plan(params[:start_lat],params[:start_lng],params[:des_lat],params[:des_lng],params[:mid_lat],params[:mid_lng]) 

    plan_arr = CSV.read("#{Rails.root}/bd09_csv/planned_path.csv")
    plan_arr = plan_arr[1, plan_arr.length]
    plan = []
    plan_arr.each do |index, lat, lng|
      plan[index.to_i] = {:index => index.to_i, :lat => lat.to_f, :lng => lng.to_f}
    end
    
    render json: {:status => "ok", :plan => plan}
  end
  
  #获取limit_num 秒内的数据 并处理经纬度数据
  def get_gps_content1(collection, limit_num) 

    time_list = []
    lat_list = []
    lng_list = []
    mlat_list = [] #处理后的维度列表
    mlng_list = []

    collection.find.sort(:_id => -1).limit(limit_num).each do |doc|  #根据输入时间信息 倒叙获取limit_num 条数据 并添加到响应列表中
      time_list.append(doc[:time])
      lat_list.append(doc[:lat].to_f)
      lng_list.append(doc[:lng].to_f)
    end

    lat_list.each do |lat|
      lat = lat.div(100) + lat%100/60
      mlat_list.append(lat)
    end

    lng_list.each do |lng|
      lng = lng.div(100) + lng%100/60
      mlng_list.append(lng)
    end
    return time_list, lat_list, lng_list, mlat_list, mlng_list
  end
  
  #计算前个点到当前点的距离和航向角
  def da_B2A(latA, latB, lngA, lngB)
    cc = Math.sin(90-latA) * Math.sin(90-latB) * Math.cos(lngB - lngA) + Math.cos(90-latA) * Math.cos(90-latB) #求出cos（c）
    if cc > 1
      puts cc
      cc = format("%.4f", cc).to_f
      puts "latA:%f\nlngA:%f\nlatB:%f\nlngB:%f" % [latA, lngA, latB, lngB]
      puts cc
    end
    if cc > 1
      puts cc
      puts "latA:%f\nlngA:%f\nlatB:%f\nlngB:%f" % [latA, lngA, latB, lngB]
    else
      distance = 6371000 * Math.acos(cc) * (Math::PI/180) # 地球半径m * 弧度（acos（cos（c））* pi/180）
      distance = format("%.4f", distance).to_f #精确到小数点后四位
      #计算角度
      dy= lngB-lngA
      dx= latB-latA
      if dx==0 and dy>0
          angle = 0
      end
      if dx==0 and dy<0
          angle = 180
      end
      if dy==0 and dx>0
          angle = 90
      end
      if dy==0 and dx<0
          angle = 270
      end
      if dx>0 and dy>0
         angle = Math.atan(dx/dy)*180/Math::PI
      elsif dx<0 and dy>0
         angle = 360 + Math.atan(dx/dy)*180/Math::PI
      elsif dx<0 and dy<0
         angle = 180 + Math.atan(dx/dy)*180/Math::PI
      elsif dx>0 and dy<0
         angle = 180 + Math.atan(dx/dy)*180/Math::PI
      end
    end
    return distance, angle #返回 距离  角度
  end

  # 将osm规划路径录入用户数据库
  def osm2mongo(collection, path_id)
    plan_bd09 = []
    plan_gps = []
   
    # 读取bd09格式的路径点
    plan_arr1= CSV.read("#{Rails.root}/bd09_csv/planned_path.csv")
    plan_arr1 = plan_arr1[1, plan_arr1.length]
    plan_arr1.each do |index, lat, lng|
      plan_bd09[index.to_i] = {:index => index.to_i, :lat => lat.to_f, :lng => lng.to_f}
    end

    # 读取gps格式的路径点
    plan_arr2= CSV.read("#{Rails.root}/equipment_csv/planned_path.csv")
    plan_arr2 = plan_arr2[1, plan_arr2.length]
    plan_arr2.each do |index, lat, lng|
      plan_gps[index.to_i] = {:index => index.to_i, :lat => lat.to_f, :lng => lng.to_f}
    end

    collection.find(:_id => path_id).update_one("$inc" => {"total" => plan_bd09.length})

    # 录入到用户数据库中
    (0..plan_bd09.length-1).each do |index|
      collection.insert_one({"path_id" => path_id,"num" => index+1, "lat_bd09" => plan_bd09[index][:lat],"lng_bd09" => plan_bd09[index][:lng], "lat_gps" => plan_gps[index][:lat], "lng_gps" => plan_gps[index][:lng]})
    end
    puts "osm2mong    end"
  end

  # 根据用户信息匹配距起始点最近的小车
  def get_closet_ugv_id
    # get 传递参数 start_lat,start_lng, des_lat,des_lng ,mid_lat,mid_lng (bd09 
    car_ip = []
    car_num = []
    car_status = [] 
    lats = []
    lngs = []
    distance = []
    path_id = nil
    puts params[:start_lat] # get请求传递的参数
    puts params[:start_lng]
    # 查询用户数据库 获取用户下的小车ip和id
    client_user = Mongo::Client.new('mongodb://127.0.0.1:27017/user_mongo')
    db= client_user.use('user_mongo')
    user_info = db[:user_info]
    user_path = db[:user_path]
  
    user_info.find.each do |doc| 
      car_ip.append(doc[:car_ip])
      car_num.append(doc[:car_num])
    end
  
    # 获取小车的当前位置和状态
    car_ip.each do |ip|
      mongoip = 'mongodb://' << ip.to_s << ':27017/ugv'
      client = Mongo::Client.new(mongoip)
      db = client.use('ugv')
      collection = db[:ugv_status_test] #获取集合
      time_list, lat_list, lng_list, mlat_list, mlng_list = get_gps_content1(collection, 1)
      lats = lats + mlat_list
      lngs = lngs + mlng_list

      collection1 = db[:ugv_info]
      collection1.find.each do |doc|
        car_status.append(doc[:car_status])
      end
    end
    puts car_status.to_s

    # 判断小车是否空闲
      # 不空闲从两个列表中移除
      car_status.each_with_index do |status,i|
        if status  == 'moving'
          car_num.delete_at(i)
          lats.delete_at(i)
          lngs.delete_at(i)
        end
      end

    # 比较小车与用户起点  返回最近的小车id
    (0..car_num.length-1).each do |i|
      distance1, angle1 = da_B2A(lats[i].to_i, params[:start_lat].to_i, lngs[i].to_i, params[:start_lng].to_i)
      puts distance1
      puts "-=-=-=="
      distance << distance1
    end
    puts distance
    closest = distance.each_with_index.min  #  [element, index]
    
    # 路径总表
    user_path.insert_one({"car_num" =>car_num[closest[1]], "start_lat_bd09" => params[:start_lat].to_f, "start_lng_bd09" => params[:start_lng].to_f, "des_lat_bd09" => params[:des_lat].to_f, "des_lng_bd09" => params[:des_lng].to_f})
    user_path.find(:car_num =>car_num[closest[1]], :start_lat_bd09 => params[:start_lat].to_f, :start_lng_bd09 => params[:start_lng].to_f, :des_lat_bd09 => params[:des_lat].to_f, :des_lng_bd09 => params[:des_lng].to_f).each do |doc|
      path_id = doc[:_id]
    end
    puts path_id
    # 根据用户提供的参数 获得规划路径
    osm_plan(params[:start_lat],params[:start_lng],params[:des_lat],params[:des_lng],params[:mid_lat],params[:mid_lng])
    # 将得到的规划路径文件储存至用户数据库中
    osm2mongo(user_path, path_id)
    # 预估小车到达时间
    car_time = closest[0].to_f /  50  # speed = 50
    # 返回 小车id 、小车据元地址A的距离、预估小车到达时间、实际小车位置
    render json:{:car_num => car_num[closest[1]], :distance => closest[0], :arrived_time => car_time, :car_lat =>lats[closest[1]], :car_lng =>lngs[closest[1]]}
    # render json:{:stauts => "ok"}
  end


## mqtt kafka
  # mqtt 消息推送
  def mqtt_pub
    client = MQTT::Client.connect('118.31.21.0', 1883)
    client.publish('test', 'hello, ruby')
    puts "已发送消息：hello, ruby"
    render json: {:status => "ok"}
  end

  # mqtt 消息接收
  def mqtt_sub
    client = MQTT::Client.connect('118.31.21.0', 1883)
    client.get('test') do |topic,message|
      puts topic
      puts message
    end
    render json: {:status => "ok"}
  end

  # 特殊路径文件
  def download_special
    send_file "sepcial.csv"
  end

  # kafka生产者
  def kafka_producer
    kafka = Kafka.new(["118.31.21.0:9092"], client_id: "my-application")
    # kafka.deliver_message("Hello, World!", topic: "test")
    producer = kafka.producer
    producer.produce("D,R,L,D,S,D,L,R,D,S", topic: "test")
    producer.deliver_messages

    render json: {:status => "ok"}
  end

  # kafka消费者
  def kafka_consumer
    # brokers = ["kafka-cluster2.base.svc.zhe800.local:9092"]
    kafka = Kafka.new(["118.31.21.0:9092"])
    group_id = "my-consumer"
    consumer = kafka.consumer(group_id: group_id)
    topic = "test"
    consumer.subscribe(topic)
    consumer.each_message do |message|
      puts "value:#{message.value}"
      msg = message.value
      socket = tcp_socket
      socket.puts(msg)
      puts "×××××××××××××××××××××× socket指令已发送 ××××××××××××××××××××××××××"
      socket.close
    end
  end


  # 测试同时下发10个顺序执行的测试命令
  def send_queue
    socket = tcp_socket
    
    # 正常下发
    socket.puts('D,R,L,D,S,D,L,R,D,S')
    # 按3,5,7优先级最高下发
    # socket.puts('D,R,R1,L,L1,S,S1,L,D,S')
    
    socket.close
    time = Time.new
    f_time = time.strftime("%H:%M:%S")
    
    l_time = "下发时间：" + f_time + "_微秒：" + time.usec.to_s
    
    render json: {:status => "ok", :time => l_time}
  end

# 绕开
  def bypass
    puts("调用成功")
    socket = tcp_socket
    socket.puts('B')
    socket.close
    sleep(8.60)

    socket = tcp_socket
    socket.puts('L')
    socket.close
    sleep(5.5)

    socket = tcp_socket
    socket.puts('D')
    socket.close
    sleep(3.6)

    socket = tcp_socket
    socket.puts('R')
    socket.close
    sleep(4.3)

    socket = tcp_socket
    socket.puts('D')
    socket.close
    sleep(13.1)

    socket = tcp_socket
    socket.puts('R')
    socket.close
    sleep(6)

    socket = tcp_socket
    socket.puts('L')
    socket.close
    sleep(6)

    socket = tcp_socket
    socket.puts('S')
    socket.close
    render json: {:status => 'ok'}, callback: params['callback']
  end

## 前端操作

  # 添加新路径点
  def new_point
    lat = params['lat']
    lng = params['lng']
    lat = lat.to_f * 100
    lng = lng.to_f * 100
    #将路径点的经纬度写入CSV文件
    if File::exists?("#{Rails.root}/demo.csv")# => true
      arr=CSV.read("#{Rails.root}/demo.csv")
      id = arr[arr.length-1,arr.length]
      i=id[0][0].to_i
      CSV.open("#{Rails.root}/demo.csv","a") do |csv|
      csv << [i+1,lat,lng]     
      end
    else
      File.new("#{Rails.root}/demo.csv","w")
      CSV.open("#{Rails.root}/demo.csv","a") do |arr|
      id = 1
      arr << ['id', 'lat', 'lng']
      arr << [id, lat, lng]
      end
    end
    render json: {:status => 'ok'}, callback: params['callback']
  end

  # 获取最新文件返回给前端显示
  def get_routes
    car = params['car']
    file_name = params['file_name']
    update_latest
    if File::exists?("#{Rails.root}/temp_csv.csv")
      File.delete("#{Rails.root}/temp_csv.csv")
    end
    routes_arr = CSV.read("#{Rails.root}/latest/latest.csv")
    routes_arr = routes_arr[1, routes_arr.length]
    routes = []
    routes_arr.each do |index, lat, lng|
      routes[index.to_i - 1] = { :lng => lng.to_f, :lat => lat.to_f, :status => 'doing'}
    end
=begin
    CSV.foreach("#{Rails.root}/test.csv") do |row, index|
      puts row
      puts index
    end
=end
    render json: {:status => 'ok', :routes => routes}, callback: params['callback']
  end

  def get_csv_files
    car = params['car']
    file_list = []
    Dir.foreach("#{Rails.root}/csv/#{car}") do |filename|
      if filename != '.' && filename != '..'
        file_list.push(filename)
      end
    end
    render json: {:status => 'ok', :file_list => file_list}, callback: params['callback']
  end

  # 设置关键路径点
  def routes
    mode = params['mode'].to_i
    if mode==50
      File.delete("#{Rails.root}/test.csv")
      File.rename("#{Rails.root}/demo.csv","#{Rails.root}/test.csv")
      render json: {:status => 'ok'} , callback: params['callback']
    else
      render json: {:status => 'error'} , callback: params['callback']
    end
    #render json: self.class.mqttget_routes(count, lngs, lats), callback: params['callback']
  end

  # 重新规划功能，停止后，未完成的剩余路径点保存为新文件
  def remain_point
    # 连接小车mongodb获取剩余点个数
    db = connet_mongdb1
    collection = db[:ugv_point]

    count = []

    collection.find.sort(:time => -1).each do |doc|
      count = doc[:id].to_i
    end

    # 读取test.csv未完成的路径点，写入test_stop.csv
    content = CSV.read("#{Rails.root}/test.csv")
    time = Time.new
    f_time = time.strftime("%Y_%m_%d_%H_%M")

    # 计算剩余路径个数
    temp = content.length - 1 - count + 1

    CSV.open("#{Rails.root}/equipment_csv/#{f_time}_P#{temp}_residual.csv","wb") do |arr|
      arr << ["id", "lat", "lng"]
      # id从1开始
      j = 1
      for i in count..content.length-1
        arr << [j, content[i][1], content[i][2]]
        j += 1
      end
    end

    # 调用同步文件方法
    w_bd09
    # 调用最新文件方法
    update_latest

    render json: {:status => "ok"}, callback: params['callback']
    # render json: {:remain => remain, :status => "ok"}, callback: params['callback']
  end

  # 下个路径点，返回给前端显示
  def count_point
    # 连接数据库
    db = connet_mongdb1
    collection = db[:ugv_point]

    count = []

    # 从数据库获取剩余下个路径点id
    collection.find.sort(:time => -1).each do |doc|
      count = doc[:id].to_i
    end

    render json: {:count => count, :status => "ok"}, callback: params['callback']
  end

  #  采集功能，上传设备坐标，不进行处理
  def upload_point
    # 调用连接小车数据库方法
    db = connet_mongdb1
    collection = db[:ugv_status_test]
    temp = []
    # 获取数据库static的值
    static = JSON.parse(Ocean.all.to_json).first['static']
    if static == true
      collection.find.sort(:time => -1).limit(1).each do |doc|  #根据输入时间信息 倒叙获取limit_num 条数据 并添加到响应列表中
        lat = doc[:lat].to_f
        lng = doc[:lng].to_f
        # 写入临时文件
        if File::exists?("#{Rails.root}/temp_csv.csv")
          arr=CSV.read("#{Rails.root}/temp_csv.csv")
          id = arr[arr.length-1,arr.length]           # 连接上一个id
          i=id[0][0].to_i
          CSV.open("#{Rails.root}/temp_csv.csv","a") do |csv|
          csv << [i+1, lat, lng]     
          end
        else
          File.new("#{Rails.root}/temp_csv.csv","w")
          CSV.open("#{Rails.root}/temp_csv.csv","a") do |arr|
          id = 1
          arr << ['id', 'lat', 'lng']
          arr << [id, lat, lng]
          end
        end
        # 调用路径处理转换方法，将坐标转换成bd09格式返回给前端
        temp = gps_bd09(lat, lng)
      end
      render json:{lat: temp[0], lng: temp[1], :status => "ok"}, callback: params['callback']
    else
      render json:{:status => "error"}, callback: params['callback']
    end
  end

  # 保存功能，前端结束采集，保存路径点为新的时间命名的csv文件
  def upload_point2

    # 调用读写文件方法，读取临时文件内容，写入设备格式文件夹下的时间命名的新的csv文件
    manage_point("temp_csv.csv")

    # 读取临时文件，写入特殊文件
    content = CSV.read("#{Rails.root}/temp_csv.csv")
    # 写入特殊文件
    File.open("#{Rails.root}/special.csv", "wb") do |csv|
      for i in 0..content.length-1
        csv << content[i]
      end
    end

    # 调用最新文件方法，更新latest.csv
    update_latest
    # 调用同步文件方法，bd09格式文件夹同步
    w_bd09
    # 调用历史记录方法，更新历史文件
    csv_history
    # 删除临时文件
    File.delete("#{Rails.root}/temp_csv.csv")
    render json: {:status => "ok"}, callback: params['callback']
  end

  # 对应更新按钮   即保存手动添加的路径点 并同步到test.csv
  def  upload_point3
    puts '1'
  end

  # 打开功能，将用户打开的文件 另存为test.csv，对应前端打开按钮。
  def cp_open_file
    file_name = params['file_name']
    Dir.foreach("#{Rails.root}/equipment_csv") do |filename|
      if filename == "#{file_name}"
        content = CSV.read("#{Rails.root}/equipment_csv/#{filename}")
        CSV.open("#{Rails.root}/test.csv", "wb") do |csv|
          for i in 0..content.length-1
            csv << content[i]
          end
        end
      end
    end
    render json: {:status => "ok"}, callback: params['callback']
  end

  # 前端设置工作模式接口
  def mode_frontend
    new_mode = params['mode'].to_i
    socket = tcp_socket
    time = Time.new
    f_time = time.strftime("%H:%M:%S")
    if [0,4,8,10,11,15,20,50].include?(new_mode)
      if new_mode == 0  #启动
        puts('启动')
        socket.puts('M')
        puts "下发时间：" + f_time + "_微秒：" + time.usec.to_s
      elsif new_mode == 4 #直行su
        # socket.puts('123')
        socket.puts('D')
        puts('直行')
        puts "下发时间：" + f_time + "_微秒：" + time.usec.to_s
      elsif new_mode == 8 #后退
        # socket.puts('123')
        socket.puts('B')
        puts('后退')
        puts "下发时间：" + f_time + "_微秒：" + time.usec.to_s
      elsif new_mode == 20 #左转
        # socket.puts('456')
        socket.puts('L')
        puts('左转')
        puts "下发时间：" + f_time + "_微秒：" + time.usec.to_s
      elsif new_mode == 15 #右转
        # socket.puts('789')
        socket.puts('R')
        puts "下发时间：" + f_time + "_微秒：" + time.usec.to_s
      elsif new_mode == 10 #停 是前端的停 不是停止 目前加入自动操作的停止
        socket.puts('S')
        puts "*"*20
        puts "下发时间：" + f_time + "_微秒：" + time.usec.to_s
        puts "*"*20
        
      #   socket.puts('M')
      end
      socket.close()
      render json: {:status => 'ok'}, callback: params['callback']
    else
      render json: {:status => 'error'}, callback: params['callback']
    end
  end

  # 测试插入充电规划路径，待完成
  # 加入到达充电桩路径点到现有文件里
  def cp_open_file1
    file_name = params['file_name']

    # 读取网格文件
    t_point = CSV.read("#{Rails.root}/charge_table.csv")

    Dir.foreach("#{Rails.root}/equipment_csv") do |filename|
      if filename == "#{file_name}"
        content = CSV.read("#{Rails.root}/equipment_csv/#{filename}")
        len = content.length
        CSV.open("#{Rails.root}/test.csv", "wb") do |csv|
          for i in 0..content.length-1
            csv << content[i]
          end
          # 循环写入后续路径
          for j in 1..t_point.length-1
            csv << [len, t_point[j][1], t_point[j][2]]
            len += 1
          end
        end
      end
    end
    render json: {:status => "ok"}, callback: params['callback']
  end






# 无人船部分
  # 通信质量更新
  def currentPosition
    web_lat = params[:currentLat].to_f
    web_lng = params[:currentLng].to_f
    boat_lat =  PlanStatus.first.lat
    boat_lng =  PlanStatus.first.lng
    distance, angle = da_B2A(web_lat, boat_lat, web_lng, boat_lng)
    puts distance
    puts "########"
    if distance < 3000
      if distance>2000
        communicate = 25
      elsif distance >1500
        communicate = 50          
      elsif distance >1000 
        communicate = 75
      else
        communicate =100
      end
      radius = 1
    else
      communicate = 0
      radius = 0
    end
    
    Ocean.first.update({:radius => radius, :communicate => communicate})
    render json: {:status => 'ok'}, callback: params['callback']
    
  end

  # 返航
  def back_path
    # 根据最近设定的航线，将航线点反序排列，生成一条返航路线  保存在latest/back.csv
    # 读取脚本生成的路网文件
    back_wgs = CSV.read("#{Rails.root}/test.csv")
    back_wgs = JSON.parse(back_wgs.to_json)
    
    # 打开bd09格式路网文件并写入
    CSV.open("#{Rails.root}/bd09_csv/back.csv", "wb") do |arr|

      arr << ["id", "lat", "lng"]
      for i in (1..back_wgs.length-1).reverse_each
        # puts i
        # 调用路径转换方法
        back_bd = wgs_bd09(back_wgs[i][1].to_f, back_wgs[i][2].to_f)
        lat = back_bd[0].div(100)  + (back_bd[0] % 100) /60
        lng = back_bd[1].div(100) + (back_bd[1] % 100) / 60
        arr << [(back_wgs.length - i).to_s, lat, lng]
      end
    end
    
    # 打开设备格式路网文件并写入
    CSV.open("#{Rails.root}/equipment_csv/back.csv", "wb") do |csv|
      csv << ["id", "lat", "lng"]
      for i in (1..back_wgs.length-1).reverse_each
        lat = back_wgs[i][1].to_f
        lng = back_wgs[i][2].to_f
        csv << [(back_wgs.length - i).to_s, lat, lng]
      end
    end
    render json: {:status => 'ok'}, callback: params['callback']
  end

  # 四点扫描
  def bountPoint
    # p1_lat = 
    # p1_lng = params[:p2_lng]
    # p2_lat =
    # p2_lng =
    # p3_lat =
    # p3_lng = 
    # p4_lat =
    # p4_lng =
    # 计算出20m 变化的 纬度
    distance = 20
    distance = 6371000 * Math.acos(cc) * (Math::PI/180) # 地球半径m * 弧度（acos（cos（c））* pi/180）
    cc = Math.sin(90-latA) * Math.sin(90-latB) * Math.cos(lngB - lngA) + Math.cos(90-latA) * Math.cos(90-latB) #求出cos（c）
    # 通过偏移量创建s型路径
    # 写进文件 
    # 返回前端


  end

  # 前端手动控制电机接口
  def control_frontend
    lng = params['lng'].to_f
    lat = params['lat'].to_f
    count = params['count'].to_i
    lefts = []
    rights = []
    delays = []
    count.times do |i|
      left = params["left_pwn#{i}"].to_i
      right = params["right_pwn#{i}"].to_i
      delay = params["delay_time#{i}"].to_i
      lefts << left
      rights << right
      delays << delay
    end
    render json: self.class.mqttget_action(count,delays,lefts,rights,lng,lat) , callback: params['callback']
  end

  # 前段设置manual电机参数
  def control_manual
    count = params['count'].to_i
    lefts = []
    rights = []
    count.times do |i|
      left = params["left_pwn#{i}"].to_i
      right = params["right_pwn#{i}"].to_i
      lefts << left
      rights << right
      self.class.mqttsend '/usv/control/1' , self.class.send_mission_manual_control(left,right)
      if(i == 0)
        render json: {:status => 'ok'} , callback: params['callback']
      end
      sleep 1
    end
    
  end

  # TODO params[:action]获取不到参数，url不能带action的参数？

  # id 取值1～8， 控制8个抽水继电器
  # action 取值0代表打开继电器，17代表关闭继电器
  def control_relay
    id = params['id'].to_i
    action = params['act'].to_i
    if (1..8) === id && [0, 17].include?(action)
      render json: self.class.send_control_relay(id, action), callback: params['callback']
    else
      render json: {:status => 'wrong_params'}, callback: params['callback']
    end
  end

  # meter 取值0.25m 0.5m 1m 1.5m 2m 2.5m 3m
  # action 0 放线 1 收线 2 电机停止
  def control_motor
    meter = params['meter'].to_i
    action = params['act'].to_i
    meter = (meter * 2).ceil
    if (0..6) === meter && (0..2) === action
      render json: self.class.send_control_motor(meter, action), callback: params['callback']
    else
      render json: {:status => 'wrong_params'}, callback: params['callback']
    end
  end

  #无人船移动端语音输入位置
  def position_mobile
    lng = params['lng'].to_f
    lat = params['lat'].to_f
    if Info.first.update({:lng => lng, :lat=>lat, :checked => false})
      render json: {:status => 'ok'}
    else
      render json: {:status => 'wrong'}
    end
  end

  #无人船前端获取语音输入位置
  def position
    info = Info.first
    if !info.checked
      info.update({:checked => true})
      render json: {:lng => info.lng, :lat => info.lat, :status => "ok"}, callback: params['callback']
    else
      render json: {:status => 'checked'}, callback: params['callback']
    end
  end

  #无人船移动端获取警告信息
  def warning_mobile
    render json: {:status => Info.first.warning}
  end

  #无人船前端设置警报信息
  def warning
    warning = params['warning'] == 'true'
    Info.first.update(:warning => warning)
    render json: {:status => 'ok'}, callback: params['callback']
  end

  # 前端一键返航指令接口
  def mode_return
    self.class.mqttsend '/usv/control/1', self.class.send_set_mode(11)
    render json: {:status => 'ok'}, callback: params['callback']
  end

  # 获取测试船体坐标数据
  def test_location
    test = Test.first
    lng = (test.lng + Random.rand(0.00001) - 0.000005).round(6)
    lat = (test.lat + Random.rand(0.00001) - 0.000005).round(6)
    result = {:lng => lng, :lat => lat}
    Test.update(result)
    render json: result, callback: params['callback']
  end

  # 获取测试传感器数据
  def test_sensor
    test = Test.first
    temperature = (test.temperature + Random.rand(1.0) - 0.5).round(2)
    ph = (test.ph + Random.rand(0.5) - 0.25).round(2)
    conductivity = (test.conductivity + Random.rand(0.2) - 0.1).round(2)
    turbidity = (test.turbidity + Random.rand(0.2) - 0.1).round(2)
    oxygen = (test.oxygen + Random.rand(0.2) - 0.1).round(2)
    result = {:temperature => temperature,
              :ph => ph,
              :conductivity => conductivity,
              :turbidity => turbidity,
              :oxygen => oxygen}
    Test.update(result)
    render json: result, callback: params['callback']
  end

  #电机解锁
  def arm
    render json: self.class.send_arm_or_disarm('arm'), callback: params['callback']
  end

  #电机上锁
  def disarm
    render json: self.class.send_arm_or_disarm('disarm'), callback: params['callback']
  end

  #获取另一个GPS模块数据
  def gps
    render json: GpsLocation.info, callback: params['callback']
  end

## 功能

  class << self
    include Communicate
    include Modbus

    def connet_mongdb #连接mongodb
      client = Mongo::Client.new('mongodb://192.168.1.156:27017/ugv')
      
      db = client.database #获取数据库
      # client = Mongo::Client.new('mongodb://ugv:123456@116.62.125.255:27017/admin')
      # db = client.use('ugv')
      # collection = db[:ugv_status_test] #获取集合
      return db
    end

    # # 封装函数，连接系统数据库
    # def connect_sys_mongodb
    #   client = Mongo::Client.new('mongodb://127.0.0.1:27017/sys')
    #   # 获取数据库
    #   db = client.database
    #   return db 
    # end

    # 封装函数，与小车的 tcp 连接
    def tcp_socket
      socket = TCPSocket.open('192.168.21.102', 8888)
      # socket = TCPSocket.open('112.74.89.58', 38752)
      return socket
    end

    def gps_bd09_1(lat, lng)
      a_lat = lat.div(100) + lat%100/60
      a_lng = lng.div(100) + lng%100/60

      temp = Coordconver.wgs_gcj(a_lng, a_lat)
      a = Coordconver.gcj_bd(temp[0], temp[1])
      return a[1], a[0]
    end

    def da_B2A(latA, latB, lngA, lngB) #计算前个点到当前点的距离和航向角
      cc = Math.sin(90-latA) * Math.sin(90-latB) * Math.cos(lngB - lngA) + Math.cos(90-latA) * Math.cos(90-latB) #求出cos（c）
      if cc > 1
        puts cc
        cc = format("%.4f", cc).to_f
        puts "latA:%f\nlngA:%f\nlatB:%f\nlngB:%f" % [latA, lngA, latB, lngB]
        puts cc
      end
      if cc > 1
        puts cc
        puts "latA:%f\nlngA:%f\nlatB:%f\nlngB:%f" % [latA, lngA, latB, lngB]
      else
        distance = 6371000 * Math.acos(cc) * (Math::PI/180) # 地球半径m * 弧度（acos（cos（c））* pi/180）
        distance = format("%.4f", distance).to_f #精确到小数点后四位
        #计算角度
        dy= lngB-lngA
        dx= latB-latA
        if dx==0 and dy>0
            angle = 0
        end
        if dx==0 and dy<0
            angle = 180
        end
        if dy==0 and dx>0
            angle = 90
        end
        if dy==0 and dx<0
            angle = 270
        end
        if dx>0 and dy>0
           angle = Math.atan(dx/dy)*180/Math::PI
        elsif dx<0 and dy>0
           angle = 360 + Math.atan(dx/dy)*180/Math::PI
        elsif dx<0 and dy<0
           angle = 180 + Math.atan(dx/dy)*180/Math::PI
        elsif dx>0 and dy<0
           angle = 180 + Math.atan(dx/dy)*180/Math::PI
        end
      end
      return distance, angle #返回 距离  角度
    end

    def get_gps_content(collection, limit_num) #获取limit_num 秒内的数据 并处理经纬度数据

      time_list = []
      lat_list = []
      lng_list = []
      mlat_list = [] #处理后的维度列表
      mlng_list = []

      collection.find.sort(:_id => -1).limit(limit_num).each do |doc|  #根据输入时间信息 倒叙获取limit_num 条数据 并添加到响应列表中
        time_list.append(doc[:time])
        lat_list.append(doc[:lat].to_f)
        lng_list.append(doc[:lng].to_f)
      end

      lat_list.each do |lat|
        lat = lat.div(100) + lat%100/60
        mlat_list.append(lat)
      end

      lng_list.each do |lng|
        lng = lng.div(100) + lng%100/60
        mlng_list.append(lng)
      end
      return time_list, lat_list, lng_list, mlat_list, mlng_list
    end

    #前端获取小车速度、角度等信息
    def get_gps_recent
      db = connet_mongdb  #获取数据库
      collection = db[:ugv_status_test]  #获取集合
      time_list, lat_list, lng_list, mlat_list, mlng_list = get_gps_content(collection, 2) # 传入 集合、限制个数  返回gps数据

      if lat_list.length == 2  #判断读取的数据是否为2条
        s, angle = da_B2A(mlat_list[0], mlat_list[1], mlng_list[0], mlng_list[1]) #计算距离m和航向角°
        # speed = s / (time_list[0] - time_list[1]) #计算速度
        speed = s / 1 #时间默认为1s
        #position = [lng_list[0], lat_list[0]]
      else #否 则未启动
        speed = 0
        angle = 0
      end
      temp = gps_bd09_1(lat_list[0], lng_list[0])

      Ocean.first.update({:speed => speed, :angle => angle})
      PlanStatus.first.update({:lng => temp[1].to_s, :lat => temp[0].to_s})

      render json:{:speed => speed, :angle => angle, :lng => temp[1].to_s, :lat => temp[0].to_s}
    end

    #判断小车是否禁止    十秒内gps在一定范围内
    def get_status_recent
      db = connet_mongdb #获取db
      collection = db[:ugv_status_test] #获取集合
      limit_num = 10  # 10条数据
      time_list, lat_list, lng_list, mlat_list, mlng_list = get_gps_content(collection, limit_num) # 传入 集合、限制个数  返回gps数据

      if lat_list.length == limit_num  #当获取的数据为10条时 小于10条数据时返回空
        d_max = 0 #最大距离
        static = false #静止标识


        for i in (0..limit_num-2)  #10条数据9个距离
          distance, angle = da_B2A(mlat_list[i], mlat_list[i+1], mlng_list[i], mlng_list[i+1]) #计算距离m
          if distance > d_max
            d_max = distance
          end

          if i == 0 and distance < 1  #当距离小于1m时记录当前位置
            less1m_position = [mlat_list[i].to_s, mlng_list[i].to_s]
          end
        end

        if d_max <= 0.7 # 判断是否静止
          static = true
          static_positon = [mlat_list[0].to_s, mlng_list[0].to_s]
        end
      end
      puts '*'*10
      puts static
      puts static_positon
      puts '*'*10
      puts d_max
      puts '*'*10
      puts mlat_list[0]
      puts mlng_list[0]
      Ocean.update({:static => static})

      render json:{:d_max => d_max, :less1m_position => less1m_position, :static => static, :static_positon => static_positon}
    end
## 车部分
    # # 封装函数，获取温度传感器的温度
    # def temp_uri(mac)
    #   # 发送http请求，获取传感器温度数据
    #   uri = "http://api.easylinkin.com/api/v1/application/data?mac=#{mac}&token=123456&cid=226"
    #   html_response = nil
    #   open(uri) do |http|
    #     html_response = http.read
    #   end
    #   result = JSON.parse(html_response)
    #   data = result["data"]

    #   # 数据处理
    #   temp_i = data[10..11].to_i(16)
    #   temp_f = data[12..13].to_i(16)
    #   temp = temp_i + temp_f.to_f/100
    #   return temp
    # end

    # # 判断温度，某个温度传感器超过50度
    # # 就产生一个指向它的csv文件
    # def judge_temp
    #   db = connect_sys_mongodb
    #   collection = db[:sys_temp]

    #   # 获取小车当前位置
    #   db1 = connet_mongdb
    #   collection1 = db1[:ugv_status_test]
    #   collection1.find.sort(:time => -1).limit(1).each do |doc_l|  #根据输入时间信息 倒叙获取limit_num 条数据 并添加到响应列表中
    #     lat_l = doc_l[:lat].to_f
    #     lng_l = doc_l[:lng].to_f
      
    #     collection.find.each do |doc|
    #       temp = doc[:temp].to_f
    #       lat = doc[:lat].to_f
    #       lng = doc[:lng].to_f
    #       # 判断温度是否大于50度
    #       if temp > 50
    #         # 获取文件列表
    #         file_list = []
    #         Dir.foreach("#{Rails.root}/equipment_csv") do |filename|
    #           if filename != '.' && filename != '..' && filename != 'test1015-2.csv'
    #             file_list.push(filename)
    #           end
    #         end

    #         # 文件名排序
    #         l_file = file_list.sort
    #         # 读取最后一个创建的文件
    #         content = CSV.read("#{Rails.root}/equipment_csv/#{l_file[-1]}")
    #         content = JSON.parse(content.to_json)

    #         # 匹配最后一行经纬度与温度传感器经纬度
    #         # 如果一样，则不产生csv文件
    #         # 不一样，则产生一个新的csv文件
    #         if content[-1][1] != lat || content[-1][2] != lng
    #           time = Time.new
    #           f_time = time.strftime("%Y_%m_%d_%H_%M")
    #           CSV.open("#{Rails.root}/equipment_csv/#{f_time}_P2.csv","wb") do |arr|
    #             arr << ["id", "lat", "lng"]
    #             arr << [1, lat_l, lng_l]
    #             arr << [2, lat, lng]
    #           end
    #         end
    #       end
    #     end
    #   end
    # end

    # # 获取到温度数据，写入mongodb数据库
    # def temp_mongo
    #   # 连接小车mongodb存放温度的集合
    #   db = connect_sys_mongodb
    #   collection = db[:sys_temp]
    #   mac_list = ["004A770211060287","004A77021106026C","004A770211060248","004A770211060240"]
    #   temp_list = []
    #   i = 1

    #   # 循环更新数据库
    #   mac_list.each do |mac|
    #     temp = temp_uri(mac)
    #     collection.update_one({id: i}, {"$set" => {temp: temp}})
    #     i += 1
    #     temp_list.append(temp)
    #   end

    #   judge_temp
    #   puts "*"*60
    #   puts temp_list
    #   puts "*"*60

    #   render json: {:status => 'ok',:temp_list => temp_list}
    # end

    # # 使用udp服务接收方向盘数据
    # def udp_wheel_socket
    #   # BasicSocket.do_not_reverse_lookup = true
    #   server = UDPSocket.new
    #   server.bind('', 1888)
    #   while true
    #     puts "程序开始"
    #     data, addr = server.recvfrom(1024)
    #     puts "接收到消息："
    #     puts data

    #     # 显示接收时间
    #     time = Time.new
    #     f_time = time.strftime("%H:%M:%S")
    #     puts "*"*20
    #     puts "^_^接收时间：" + f_time + "_微秒：" + time.usec.to_s
    #     puts "*"*20

    #     temp = data.split(",")
        
    #     # 判断方向盘有非零数据传来就发送给小车
    #     if temp[0].to_s != "0" or temp[1].to_s != "0" or temp[2].to_s != "0"
    #       client_to_car(data)
    #     end
    #   end
    # end

    # # 使用udp协议转发方向盘数据给小车
    # def client_to_car(msg)
    #   puts "调起socket准备发送：#{msg}"
    #   time = Time.new
    #   f_time = time.strftime("%H:%M:%S")

    #   socket = UDPSocket.new
    #   socket.connect("112.74.89.58", 38699)
    #   # socket.puts "123"
    #   socket.write(msg)
    #   puts "#"*20
    #   puts "@_@下发时间：" + f_time + "_微秒：" + time.usec.to_s
    #   puts "#"*20
    #   socket.close
    # end

    # def test_csv
    #   CSV.foreach("#{Rails.root}/test.csv") do |row|
    #     puts row
    #   end
    # end

    # def write_location (sheet, i)
    #   plan_status = PlanStatus.first
    #   sheet.row(i).push i, plan_status.lng, plan_status.lat, Time.now.to_s
    # end

    # def start_udp_server
    #   socket = UDPSocket.new
    #   socket.bind("192.168.1.100", 1999)
    #   loop do
    #     msg = socket.recvfrom(1024)
    #     arr = msg[0].split(',')
    #     puts msg[0]
    #     case arr[0]
    #     when '$GPGGA'
    #       lat = arr[2].to_f/100
    #       lng = arr[4].to_f/100
    #       puts '*****lat, lng*****'
    #       puts lat, lng
    #       GpsLocation.first.update(:lat => lat, :lng => lng)
    #     when '$GPRMC'
    #       lat = arr[3].to_f/100
    #       lng = arr[5].to_f/100
    #       puts '*****lat, lng*****'
    #       puts lat, lng
    #       GpsLocation.first.update(:lat => lat, :lng => lng)
    #     when '#HEADINGA'
    #       heading = arr[12].to_f
    #       puts '*****heading*****'
    #       puts heading
    #       GpsLocation.first.update(:heading => heading)
    #     else
    #       nil
    #     end
    #   end
    # end

    # def send_udp_datagram
    #   socket = UDPSocket.new
    #   socket.connect("192.168.1.100", 1999)
    #   arr = ['$GPGGA,030940.00,3053.2782871,N,12143.5443069,E,1,20,0.8,25.4571,M,12.935,M,99,0000*6D',
    #   '$GPGLL,3053.2782871,N,12153.5443069,E,030940.00,A,D*6B',
    #   '$GNGSA,M,3,01,03,08,11,17,18,22,28,30,,,,1.6,0.8,1.4*26',
    #   '$GNGSA,M,3,141,147,148,150,153,,,,,,,,1.6,0.8,1.4*12',
    #   '$GNGSA,M,3,45,51,52,54,60,61,,,,,,,1.6,0.8,1.4*28',
    #   '$GPGSV,3,1,12,01,68,033,53,22,41,107,47,30,42,240,35,03,35,139,38*71',
    #   '$GPGSV,3,2,12,17,27,290,38,08,23,071,40,07,29,204,,19,05,274,*75',
    #   '$GPGSV,3,3,12,06,04,225,,28,55,328,51,11,54,035,51,18,41,041,47*73',
    #   '$BDGSV,2,1,05,141,50,147,49,147,68,171,51,148,69,286,51,150,75,272,51*60',
    #   '$BDGSV,2,2,05,153,52,255,41,,,,,,,,,,,,*6A',
    #   '$GLGSV,2,1,06,51,70,251,52,60,17,042,44,52,41,320,51,61,49,358,48*6B',
    #   '$GLGSV,2,2,06,45,12,055,34,54,39,283,45,,,,,,,,*65',
    #   '$GPRMC,030940.00,A,3053.2782871,N,12153.5443069,E,000.037,218.4,270718,0.0,W,D*25',
    #   '$GPVTG,218.393,T,218.393,M,0.037,N,0.068,K,D*2C',
    #   '#HEADINGA,COM2,0,60.0,FINESTEERING,2011,443398.000,00000000,0000,1114;SOL_COMPUTED,NARROW_INT,1.396890879,220.623992920,-6.505328655,0.0,0.0158,0.0169,"0004",12,12,12,12,0,0,0,0*9fe42a98']
    #   while true
    #     socket.write(arr[rand(15)])
    #     sleep 0.3
    #   end
    # end

    # def test
    #   array = [["fe1c8f010121dea521006d5593129e215e48a6ffffffa6ffffff1b00e7fffbffb78401c0"],
    #            ["fe1ca401012136a8210074559312a5215e48f80c0000f80c000023001400fcffad847f36"],
    #            ["fe1cb301012156ab21006e559312a7215e48080200000802000017000900fcff9f844420"],
    #            ["fe1c8f010121dea521006d5593128e215e48a6ffffffa6ffffff1b00e7fffbffb78401c0"],
    #            ["fe1ca401012136a8210074559312a8215e48f80c0000f80c000023001400fcffad847f36"],
    #            ["fe1cb301012156ab21006e559312a9215e48080200000802000017000900fcff9f844420"],
    #            ["fe1c8f010121dea521006d5593126e215e48a6ffffffa6ffffff1b00e7fffbffb78401c0"],
    #            ["fe1ca401012136a8210074559312a1215e48f80c0000f80c000023001400fcffad847f36"],
    #            ["fe1cb301012156ab21006e55931257215e48080200000802000017000900fcff9f844420"],
    #            ["fe1c8f010121dea521006d5593125e215e48a6ffffffa6ffffff1b00e7fffbffb78401c0"],
    #            ["fe1ca401012136a821007455931265215e48f80c0000f80c000023001400fcffad847f36"],
    #            ["fe1cb301012156ab21006e559312aa215e48080200000802000017000900fcff9f844420"]]
    #   while true do
    #     mqttsend '/usv/status', array[rand(12)].pack('H*')
    #     sleep 0.03
    #   end
    # end
  end
end
