package eprint::admin_mail;
use strict;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use Apache2::RequestUtil ();
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Request::Common;
use misc;
use session;

use sql ();
use Data::Dumper;
use Text::CSV_XS;

require configuration;

sub handler {
    my ($r, $log, $dbh, $var) = @_;
print START "MAILING HANDLER HERE **********\n";

    session::r($r);
    session::log($log);
    session::dbh($dbh);

	if ( $r->param('clean_in') ) {
print STDERR "CALL Clean In \n";
		return clean_data_in( $r, $log, $dbh, $var );
	}
	
	return unless $r->param('dirty_in');

	my $dir = $r->document_root . '/mail_data/dirty_in';
	my $out = $r->document_root . '/mail_data/dirty_out';
	my $rule_file = $r->document_root . '/mail_data/rules.csv';
	
	opendir my $dirhandle, $dir or die "Couldn't open project directory ($dir): $!";
    
    while (my $name = readdir($dirhandle)) {

        # Only display non-hidden files (no dirs,etc.)
        next if substr($name, 0, 1) eq '.' || ! -f "$dir/$name";

		my $rule = get_rules($rule_file, $dbh);
print STDERR "HAVE RULES: ", Dumper($rule);

		my $start;
		my $csv = Text::CSV_XS->new({binary => 1});

		open F, "$dir/$name" or die $!;
		open O, ">$out/$name" or die $!;

		while (<F>) {
			my $line = $_;
			$line =~ s/[\r\n]+//g;
			$start++;

		 	next unless $start > 1;



			my $status = $csv->parse($line);
 			my ($cde, $str, $pos, $recno) = $csv->error_diag ();
			my $bad = $csv->error_input ();

print STDERR "HAVE PARSE STATUSS: $status - $str BAD: $bad \n";

			my @data =  $csv->fields();

			print STDERR "NEW LINE DATA @data \n";

			#my @data = misc::trim( $csv->fields() );
			next unless $data[0];

			#print STDERR "NEW LINE $start - $data[4] -- $data[5] : \n ";

			@data = clean_data($dbh, \@data, $rule);

			next unless $data[0];

			print STDERR "NEW LINE 2 - $data[0]:  $data[4] -- $data[5] : \n\n ";
			
			$csv->print(\*O, \@data);
			print O "\n";
		}
		close(F);
		close(O);

	}
    
    closedir $dirhandle or die "Couldn't close project directory: $!";
}

sub get_rules {
	my $file = shift;
	my $csv = Text::CSV_XS->new();

	open F, "$file" or die $!;
	my $rule;

	while (<F>) {
		next if $_ =~ /\#/;

		my $status = $csv->parse($_);
		my @data =  $csv->fields();

		next unless $data[0];

		push @{$rule}, { rule   => $data[2],
						 field  => $data[1],
						 action => $data[0],
					   };
	}

	close(F);
	return $rule;

}

sub clean_data {
	my ( $dbh, $data, $rules ) = @_;

	map {
		my $x = $_->{rule};
		my $i = $_->{field} - 1;
		my $d =  @$data[$i] =~ /$x/;

#		print STDERR "HAVE RULE: $d - '$x' - $_->{action} - $i - $t  \n";

		if ( $d ) {
			if ( $_->{action} eq 'string' ) {
				@$data[$i] =~ s/$x//g;
			} elsif ( $_->{action} eq 'field' ) {
				@$data[$i] = '';
			} elsif ( $_->{action} eq 'row' ) {
				@$data[0] = '';
				
			}
		}
		

	} @$rules;

	return @$data;

}

sub clean_data_in {
    my ($r, $log, $dbh, $var) = @_;

	my $dir = $r->document_root . '/mail_data/clean_in';
	
	opendir my $dirhandle, $dir or die "Couldn't open project directory ($dir): $!";
    
    while (my $name = readdir($dirhandle)) {

        # Only display non-hidden files (no dirs, etc.)
        next if substr($name, 0, 1) eq '.' || ! -f "$dir/$name";

		open F, "$dir/$name" or die $!;

		my $start;
		my $csv = Text::CSV_XS->new();
		my $ins = $dbh->prepare(q{
			INSERT INTO marketing_data (location, 	name, 		customer, 		street_name, 
										suite,		city, 		province, 		postal_code, 	
										phone, 		mail_type, 	last_order, 	delivery_minutes
			) VALUES (?,?,?,?, ?,?,?,?, ?,lower(?),?,? ) 
		});
		my $del = $dbh->prepare(q{
			DELETE FROM marketing_data WHERE location = ? 
			  AND postal_code = ?  AND phone = ?
		});

		while (<F>) {
		
			my $status = $csv->parse($_);

			my @data =  $csv->fields();

			next unless @data[0];

			map {
				$_ = undef unless $_;
			} @data;

			my @del = ($data[0], $data[7], $data[8]);
			$del->execute(@del);
			print STDERR "DELETE DATA: @del \n";

			$ins->execute(@data);

		}
		close(F);

	}
    
    closedir $dirhandle or die "Couldn't close project directory: $!";
}

1;
