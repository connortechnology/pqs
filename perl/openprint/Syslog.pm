use strict;
package openprint::Syslog;
our @ISA = qw( openprint::Object );
use openprint ();
require openprint::Object;
require openprint::Host;

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults $dbh %severities %facilities );
$dbh = undef;
$debug = 1;
$table = 'systemevents';
$serial = 'systemevents_id_seq';
%fields = (
	id	=>	'id',
 customerid => 'customerid',
 receivedat => 'receivedat',
 devicereportedtime => 'devicereportedtime',
 facility => 'facility',
 priority => 'priority',
 fromhost => 'fromhost',
 message => 'message',
 ntseverity => 'ntseverity',
 importance => 'importance',
 eventsource => 'eventsource',
 eventuser => 'eventuser',
 eventcategory => 'eventcategory',
 eventid => 'eventid',
 eventbinarydata => 'eventbinarydata',
 maxavailable => 'maxavailable',
 currusage => 'currusage',
 minusage => 'minusage',
 maxusage => 'maxusage',
 infounitid  => 'infounitid',
 syslogtag => 'syslogtag',
 eventlogtype => 'eventlogtype',
 genericfilename => 'genericfilename',
 systemid => 'systemid',
);
%find_fields = (
);
%defaults = (
);

%severities = (
	0	=> 'emerg',
	1	=> 'alert',
	2	=> 'crit',
	3	=> 'error',
	4	=> 'warning',
	5	=> 'notice',
	6	=> 'info',
	7	=> 'debug',
);

%facilities = (
0 => 'kern',
1 => 'user',
2 => 'mail',
3 => 'daemon',
4 => 'auth',
5 => 'syslog',
6 => 'lpr',
7 => 'news',
8 => 'uucp',
9 => 'cron',
10 => 'security',
11 => 'ftp',
12 => 'ntp',
13 => 'logaudit',
14 => 'logalert',
15 => 'clock',
16 => 'local0',
17 => 'local1',
18 => 'local2',
19 => 'local3',
20 => 'local4',
21 => 'local5',
22 => 'local6',
23 => 'local7',
);

1;
__END__
