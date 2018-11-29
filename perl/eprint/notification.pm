package eprint::notification;

use strict;

use session;
use Data::Dumper;

sub handler {


	file_upload();


}


sub file_upload {


	my $dbh = session::dbh;
	my $var;

	my $list  = $dbh->selectall_arrayref(q{
		SELECT * from tbl_projects WHERE strstatus = 'Waiting For Files' order by 1 desc Limit 5
	}, {Slice => {}} ); 

	print STDERR "HAVE lIST ", Dumper($list);

	my $from 	= configuration::get_value(undef, $dbh, 'FileUploadEmail');
	my $file 	= '/email/content/notification/file_upload.html';
	my $subject = 'File Upload';
	my $info;


	foreach my $p ( @{$list} ) {

		my $order = $dbh->selectrow_hashref(q{
			SELECT * from tbl_orders o, tbl_order_contents oc where oc.lngprojectindex = ?
			AND oc.lngorderid = o.lngorderid
		}, undef, $p->{lngprojectindex} );

		print STDERR "HAVE ORDER", Dumper($order);

		my $to		=  $order->{stremail};	
		$info->{pid} = $p->{lngprojectindex};

		send_email( $var, $to, $from, $subject, $file, $info); 


	}


}

sub send_email {

	my ($var, $to, $from, $subject, $file, $info ) = @_;

	my $r 	= session::r;
	my $log = session::log;
	my $dbh = session::dbh;

     my %mail = (
         SMTP    => configuration::get_value( $log, $dbh, 'Mail Server'),
         FROM    => $from,
         TO      => $to,
         SUBJECT => $subject
     );

	 misc::email_with_template($r, $log, $dbh, $file, \%mail, $info);



	return 1;
	
}

1;

__END__
`
