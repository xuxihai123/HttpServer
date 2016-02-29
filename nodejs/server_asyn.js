var config = {
    port : 8080,
    root : process.cwd(),
};
var net = require('net'),
path = require('path'),
fs = require('fs'),
request = {},
response = {},
MIME = {
    text : 'text/plain',
    html : 'text/html',
    css : 'text/css',
    js : 'application/javascript',
    json : 'application/json'
};

function formatDate(date, style) { //date format util
    var y = date.getFullYear();
    var M = "0" + (date.getMonth() + 1);
    M = M.substring(M.length - 2);
    var d = "0" + date.getDate();
    d = d.substring(d.length - 2);
    var h = "0" + date.getHours();
    h = h.substring(h.length - 2);
    var m = "0" + date.getMinutes();
    m = m.substring(m.length - 2);
    var s = "0" + date.getSeconds();
    s = s.substring(s.length - 2);
    return style.replace('yyyy', y).replace('MM', M).replace('dd', d).replace('HH', h).replace('mm', m).replace('ss', s);
}

function parse_headers(content) {
    var array = content.match(/^(.*)\s(\/.*)\s(HTTP\/\d\.\d)/);
    request.method = array[1];
    request.uri = array[2];
    request.protocol = array[3];
    var lines = content.split(/\n/);
    for (var i = 0; i < lines.length; i++) {
        var sublines = lines[i].match(/^([^()<>\@,;:\\"\/\[\]?={} \t]+):\s*(.*)/i);
        sublines && (request[sublines[1]] = sublines[2]);
    }
}

function init_response(request) {
    var uri = request.uri;
    if (/\?.*/.test(uri)) {
        uri = uri.replace(/\?.*/, "");
    }
    if (/\/$/.test(uri)) {
        uri += "index.html";
    }
    if (/\w+\.html$/.test(uri)) {
        response.mime = MIME.html;
    } else if (/\w+\.css$/.test(uri)) {
        response.mime = MIME.css;
    } else if (/\w+\.js$/.test(uri)) {
        response.mime = MIME.js;
    } else if (/\w+\.json/.test(uri)) {
        response.mime = MIME.json;
    } else if (/\w+\.do/.test(uri)) {
        if (request.$Referer) {
            var subffix = uri.replace(/(\w+)\.do/, "$1.json");
            var prefix = request.$Referer.replace(/htmls\/(.*\/)\w+\.html$/, "/data/$1");
            var uri = prefix + subffix;
            response.mime = MIME.json;
        } else {
            return 1;
        }
    } else {
        response.mime = MIME.html;
    }
    response.resource = path.join(config.root, uri);
}

function resp_success(socket, resource) {
    socket.write("HTTP/1.0 200 OK\n");
    socket.write("Content-Type: " + response.mime + ";charset: UTF-8\n");
    socket.write("Date: " + new Date() + "\n");
    socket.write("Server: xyserver\n");
    socket.write("\n");
    fd = fs.openSync(resource, "r");
    var buffer = new Buffer(512);
    while (true) {
        var flag = fs.readSync(fd, buffer, 0, 512, null);
        socket.write(buffer.slice(0, flag));
        if (flag < 512) {
            break;
        }
    }
}

function resp_error(socket, status, message) {
    socket.write("HTTP/1.0 " + status + " " + message + "\n");
    socket.write("Content-Type: " + MIME.html + ";charset: UTF-8\n");
    socket.write("Date: " + new Date() + "\n");
    socket.write("Server: xyserver\n");
    socket.write("\n");
    socket.write("<html><head><title>error</title></head><body>error message:" + message + "</body></html>");
}
function accept_request(socket) {
    socket.on('data', function (data) {
        var req_msg = data.toString("utf-8");
        parse_headers(req_msg);
        console.log(formatDate(new Date(), "yyyy-MM-dd HH:mm:ss") + " " + request.method + " " + request.uri); //log
        var status = init_response(request);
        if (!status) {
            fs.exists(response.resource, function (exists) {
                    resp_success(socket, response.resource);
                    socket.destroy();
                // if (exists) {
                //     fs.stat(response.resource, function (err, stats) {
                //         if (!err && stats.isFile()) {
                //             resp_success(socket, response.resource);
                //             socket.destroy();
                //         } else {
                //             resp_error(socket, 500, "Bad Request");
                //             socket.destroy();
                //         }
                //     });
                // } else {
                //     resp_error(socket, 404, "Not Found");
                //     socket.destroy();
                // }
            });
        } else {
            resp_error(socket, 500, "Bad Request");
            socket.destroy();
        }
    });

    socket.on('error', function (e) {
        console.log(e);
    });
}
function start() {
    var httpServer = net.createServer();
    httpServer.on('connection', function (socket) {
        accept_request(socket);
    });
    httpServer.listen(config.port);
    console.log("http server running in http://127.0.0.1:" + config.port);
}

function main() { //parse args
    var argv = process.argv.splice(2);
    if (argv && argv.length != 0) { //user config
        var argstr = argv.join(" ");
        argstr = " " + argstr + " ";
        if (/\s-h\s/.test(argstr)) {
            console.log("use case:\n         node server.js -p8080 -r /home/toor/webapp");
            return;
        }
        if (/\s-p\s*\d{2,5}\s/.test(argstr)) {
            config.port = argstr.match(/\s-p\s*(\d+)\s/)[1];
        }
        if (/\s-r\s+\S+\s/.test(argstr)) {
            config.root = argstr.match(/\s-r\s+(\S+)\s/)[1];
        }
    }
    start();
}
main();
