#!/usr/bin/env perl

# this is a nonblock socket http server
use warnings;
use Socket;
use Cwd;
use URI;
use POSIX qw(strftime);
use File::Spec;
use POSIX ":sys_wait_h";
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

my $port = 8080;     #port
my $root = getcwd;
my %request;         #save headers
my $mime;
my %mime = (
    "text" => "text/plain",
    "html" => "text/html",
    "css"  => "text/css",
    "js"   => "application/javascript",
    "json" => "application/json"
);
my $quit = 0;
$SIG{INT} = $SIG{TERM} = sub {
    $quit++;
    exit(0);
};

sub REAPER {
    while ( ( my $pid = waitpid( -1, WNOHANG ) ) > 0 ) {
        print "SIGCHLD pid $pid\n";
    }
}
$SIG{CHLD} = \&REAPER;

sub main {
    my $argstr = join( " ", @ARGV );    #server -p8080 -r /home/toor
    $argstr = " $argstr ";
    if ( $argstr =~ /\s-h\s/ ) {
        print "usage:\n";
        print "      perl server.pl -p8080 -r /home/toor/webapp\n";
        exit(0);
    }
    if ( $argstr =~ /\s-p\s*(\d{2,5})\s/ ) {
        $port = $1;
    }
    if ( $argstr =~ /\s-r\s?(\S+)\s/ ) {
        $root = $1;
    }
    socket( server_socket, AF_INET, SOCK_STREAM, getprotobyname('tcp') )
        or die "Socket $!\n";
    setsockopt( server_socket, SOL_SOCKET, SO_REUSEADDR, 1 )
        or die "Can't set SO_REUSADDR: $!";
    my $my_addr = sockaddr_in( $port, INADDR_ANY );

    bind( server_socket, $my_addr ) or die "Bind $!\n";

    listen( server_socket, 5 ) || die "Listen $!\n";

    print "http server start in http://127.0.0.1:/$port\n";
    print "http server work  in path $root\n";
    while ( !$quit ) {
        accept( client_socket, server_socket ) || do {

            # try again if accept() returned because a signal was received
            next if $!{EINTR};
            die "accept: $!";
        };
        defined( $pid = fork ) || die "Fork: $!\n";
        if ( $pid == 0 ) {
            &accept_request(client_socket);
            exit(0);
        }
        else {
            close(client_socket);
        }
    }

}

sub accept_request {    # handle a request
                                      # my $socket = shift;
    &parse_headers(client_socket);    #parse
    my $uri = $request{'uri'};
    if ( !$uri ) {
        close(client_socket);
        return;
    }
    $now = strftime( "%Y-%m-%d %H:%M:%S", localtime )
        ;                             #my $now = `date`; # $now =~ s/\n//;
    print "$now $request{'method'} $uri\n";
    $uri =~ s/(\?.*)// if ( $uri =~ /\?.*/ );
    if ( $uri =~ /\w+\.html$/ ) {
        $mime = $mime{'html'};
    }
    elsif ( $uri =~ /\w+\.css$/ ) {
        $mime = $mime{"css"};
    }
    elsif ( $uri =~ /\w+\.js$/ ) {
        $mime = $mime{"js"};
    }
    elsif ( $uri =~ /\w+\.json$/ ) {
        $mime = $mime{"json"};
    }
    elsif ( $uri =~ /\w+\.svg$/ ) {
        $mime = "image/svg+xml";
    }
    elsif ( $uri =~ /\w+\.do$/ ) {
        $mime = $mime{"json"};
        my $prefix;
        my $suffix = $uri;
        my $refer  = $request{'$Referer'};
        if ( $refer && $refer =~ /htmls(\/.*\/)\w+\.html/ ) {
            $prefix = "/data$1";
            $suffix =~ s/\/(\w+)\.do/$1.json/;
            $uri = "$prefix$suffix";
        }
        else {
            $suffix =~ s/\/(\w+)\.do/$1.json/;
            $uri = "/data/$suffix";

            # resp_error( 500, "Bad Request" );
            # close(client_socket);
            # exit(1);
        }
    }
    else {
        $mime = "text/html";
    }
    my $filename = File::Spec->catfile( $root, $uri );
    if ( -e -f $filename ) {
        send_success($filename);
    }
    elsif ( -e -d $filename ) {
        if ( -e -f "$filename/index.html" ) {
            send_success("$filename/index.html");
        }
        else {
            resp_filelist($filename);
        }
    }
    else {
        resp_error( 404, "Not Found" );
    }
    close(client_socket);
}

sub parse_headers {

    # my ($socket) = @_;    #client socket
    my $content = "";
	my $flags=fcntl(client_socket, F_GETFL, 0) || die $!; # Get the current flags 
	$flags |= O_NONBLOCK; # Add non-blocking to the flags
	fcntl(client_socket, F_SETFL, $flags) || die $!; # Set the flags on the f
    while (1) {
        my $buffer;
        my $flag = sysread(client_socket, $buffer, 1024);
        $content .= $buffer;
        # last if ( $flag < 1024 );
    }

    if ( $content =~ m/^(.*)\s(\/.*)\s(HTTP\/\d\.\d)/ ) {
        $request{'method'}   = $1;
        $request{'uri'}      = URI::Escape::uri_unescape($2);
        $request{'protocol'} = $3;
    }
    my @header = split( /\n/, $content );
    foreach (@header) {
        if (/^([^()<>\@,;:\\"\/\[\]?={} \t]+):\s*(.*)/i) {
            $request{$1} = $2;
        }
    }
}

sub resp_headers {
    print client_socket "HTTP/1.0 200 OK\n";
    print client_socket "Content-Type: $mime;charset: utf-8\n";
    print client_socket "Date: $now\n";
    print client_socket "Server: xyserver\n";
    print client_socket "\n";
}

sub resp_filelist {
    my ($directory) = shift;
    opendir( DIR, $directory ) or die "cannot open $directory:$!";
    resp_headers();
    ( my $shortdir = $directory ) =~ s{$root}{};
    $shortdir =~ s/\/\//\//g;
    print client_socket
        "<html><head><meta http-equiv='Content-Type' content='text/html; charset=utf-8' /> <title>Index of ./</title></head><body><h1>Directory:$shortdir</h1><table border='0'><tbody>";
    print client_socket
        "<tr><td><a href='../'>Parent Directory</a></td><td></td><td></td></tr>";
    foreach ( sort readdir DIR ) {
        next if (/^\./);
        my @info = stat("$directory/$_");
        ( my $href = "$shortdir/$_" ) =~ s/\/\//\//g;
        $href = "$href/" if ( -d "$directory/$_" );
        my $size = $info[7];
        my $mtime = strftime( "%Y-%m-%d %H:%M:%S", localtime( $info[9] ) );
        $href =~ s/\/\//\//g;
        print client_socket
            "<tr><td><a href='$href'>$_</a></td><td style='text-align:right'>$size  bytes</td><td> $mtime</td></tr>";
    }
    closedir DIR;
    print client_socket "</tbody></table></body></html>";
}

sub resp_error {    #status, message
    my ( $status, $error ) = @_;
    print client_socket "HTTP/1.0 $status $error\n";
    print client_socket "Content-Type: text/html;charset: utf-8\n";
    print client_socket "Date: $now\n";
    print client_socket "Server: xyserver\n";
    print client_socket "\n";
    print client_socket
        "<html><head><title>Http Error</title></head><body><h2>Http Error...</h2><p>errror status:$status</p><pre>error message:$error</pre><hr><i><small>Powered by javaway</i></body></html>";
}

sub send_success {
    my $filename = shift;
    resp_headers();
    open FILE, "<$filename"
        or die "cannot open $filename:$!";
    foreach (<FILE>) {
        print client_socket $_;
    }
}

main();

