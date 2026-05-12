import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from OpenSSL import crypto
from datetime import datetime

#######################################################
def get_expired_date(file_location):
    try:
        cert = crypto.load_certificate(crypto.FILETYPE_PEM, open(file_location).read())
        expired_date = cert.get_notAfter()
        timestamp = expired_date.decode('utf-8')
        only_date = datetime.strptime(timestamp, '%Y%m%d%H%M%S%z').date().isoformat()
        #return (datetime.strptime(timestamp, '%Y%m%d%H%M%S%z').date().isoformat())
        unix_time = datetime.strptime(timestamp, '%Y%m%d%H%M%S%z')
        unix_time = int(unix_time.timestamp())
        return(str(unix_time) + "," + only_date)

    except:
        return "00000000001,1999-01-01"
#######################################################
class SimpleHTTPRequestHandler(BaseHTTPRequestHandler):

    def do_GET(self):
        try:
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()

            folder = r'/etc/haproxy/ha_ssl/'
            for file_list in os.listdir(folder):
                parm = "/etc/haproxy/ha_ssl/" + file_list
                date_is = get_expired_date(parm)
                
                self.wfile.write(b'%s,%s\n' %(file_list.encode(),date_is.encode()) )
                #self.wfile.write(b'%s\n' %date_is.encode() )

        except:
            self.send_response(404)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(b'404 - Not Found')

httpd = HTTPServer(('127.0.0.1', 8769), SimpleHTTPRequestHandler)
httpd.serve_forever()
#######################################################
