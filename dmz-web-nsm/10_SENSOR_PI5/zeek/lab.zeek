# Lab: Pi5 sensor LAN real (espejo puerto 1 del GS105Ev2)
@load local
@load policy/tuning/json-logs.zeek
redef Site::local_nets += { 192.168.1.0/24 };
redef Log::default_rotation_interval = 1 hr;
redef AF_Packet::buffer_size = 64 * 1024 * 1024;
redef AF_Packet::fanout_id = 23;
redef LogAscii::json_timestamps = JSON::TS_ISO8601;
