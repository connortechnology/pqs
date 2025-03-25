use strict;
use warnings;

package openprint::employee_production_labels;
use Date::Calc qw(Add_Delta_Days Date_to_Days check_date );

use openprint ();
use vars qw{ $log $dbh %config %variable %param };
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;
*variable = \%openprint::variable;
*param = \%openprint::param;

require openprint::Label;
require openprint::LabelType;
require openprint::Email;

sub index {
} # end sub index

sub _label {
	my $Label = $variable{Label} = new openprint::Label( $param{id} );
	if ( $param{id} and ! $$Label{id} ) {
		$variable{error} .= "Invalid label specified.  Label $param{id} does not exist.";
		return;
	} # end if
	if ( $param{action} eq 'update' ) {
		if ( exists $param{value} ) {
			$param{value} =~ s/<br\/>/\n/ig;
			$Label->set_data($param{field}=>$param{value});
		} elsif ( exists $param{location_id} ) {

			my $old_location_id = $Label->get_data($param{field}.'_location_id');
			$Label->set_data( $param{field}.'_location_id' => $param{location_id} );

			if ( $param{location_id} ) {

				my $OldLocation = openprint::Location->find_one(id=>$old_location_id) if $old_location_id;
				my $NewLocation = openprint::Location->find_one(id=>$param{location_id});
				if ( $NewLocation ) {
					if ( $OldLocation ) {
						my $old = $Label->get_data( $param{field} );
						my $oldaddress = $OldLocation->address_formatted();
						$oldaddress =~ s/\n/<br\/>/g;
						my ( $first, $last ) = $old =~ /(.*)$oldaddress(.*)/m;
						my $newaddress = $1.$NewLocation->address_formatted().$2;
						$newaddress =~ s/\n/<br\/>/g;
						$Label->set_data($param{field}=>$newaddress);
					} else {
						my $newaddress = $NewLocation->address_formatted();
						$newaddress =~ s/\n/<br\/>/g;
						$Label->set_data($param{field}=>$newaddress);
					}
				} else {
					$variable{error} .= 'Location not found.';
				}
			}
		} # end if

		$variable{error} .= $Label->save();
	} elsif ( $param{action} eq 'get' ) {

	} elsif ( $param{action} eq 'getnohtml' ) {
		$variable{PageContent} = join('', map { $_ ? $_ : () } ( $Label->get_data($param{field})) );
		$variable{PageContent} =~ s/<br\/>/\n/ig;
	} # end if
} # end sub _label

sub label {
	if ( $param{type_id} and !$param{id} ) {
		my $Label = $variable{Label} = new openprint::Label();
		$variable{error} .= $Label->save({
				type_id		=>	$param{type_id},
				reference	=>	$param{reference},
				docket		=>	$param{docket},
				});
		$variable{ExternalRedirect} = $Label->url() if !$variable{error};
		return;
	}
		
	my $Label = $variable{Label} = new openprint::Label($param{id});
	if ( $param{function} and $param{function} eq 'Send' ) {
		my $email_template = ssi::slurp_content( '/email_template.html' );
		my @attachments;
		my %info;
		$info{ReplacementText} = $param{body};
		$info{Label} = $Label;

		$_ = MIME::QuotedPrint::encode_qp( Encode::encode('utf-8', ssi::variable_substitution( \$email_template, \%info ) ) );
		push @attachments, ('', $_, 'text/html', 'quoted-printable');

		my $content = ssi::slurp_content( '/email_content/label.html' );
		push @attachments, $Label->Type()->name(). ' for docket ' . $Label->docket().'.html', 
			 MIME::QuotedPrint::encode_qp( Encode::encode('utf-8',
						 ssi::variable_substitution( \$content, \%info ) ) ), 'text/html', 'quoted-printable';

		my $Project = $Label->Project();
		my $CSR;
		if ( $Project and $Project->Company()->salesrep_id() ) {
			$CSR = new openprint::User( $Project->Company()->salesrep_id() );
		} # end if


		my $Email = new openprint::Email();
		$variable{information} .= $Email->send(
#TO  =>  'iconnor@point-one.com',
				TO  =>  [ split(',', $param{to}) ],
				( $CSR ? ( CC => sprintf('"%s" <%s>', $CSR->name(), $CSR->email() ) ) : () ),
				FROM    =>  $param{from},
				SUBJECT =>  $param{subject},
				ATTACHMENTS =>  \@attachments,
				);
		(new openprint::Log())->save({
				action=>'Send PackingSlip', 
				Object=>$Label,
				note=> 'Emailed from ' . $param{from} . ' to the following recipients:<br/>' . $variable{information} });

		$variable{ExternalRedirect} = '/employee/production/labels/label.html?id='.$Label->id();
	} elsif ( $param{action} and $param{action} eq 'pdf' ) {
		my %info;
		$info{Label} = $Label;

		my $content = ssi::slurp_content( '/email_content/label.html' );
		$content = Encode::encode('utf-8', ssi::variable_substitution( \$content, \%info ) );

		my $file_base = $Label->Type()->name().$$Label{id};
        #push @attachments, ($file_base.'.html', MIME::QuotedPrint::encode_qp($invoice_html), 'text/html', 'quoted-printable');
		if ( File::Slurp::write_file('/tmp/'.$file_base.'.html', { atomic => 1, err_mode=>'carp' }, \$content ) ) {
			`wkhtmltopdf -q -s Letter --print-media-type "/tmp/$file_base.html" "/tmp/$file_base.pdf"`;
			my $content_pdf = File::Slurp::read_file( "/tmp/$file_base.pdf" );
			unlink "/tmp/$file_base.html";
			unlink "/tmp/$file_base.pdf";
			if ( $content_pdf ) {
				$openprint::r->content_type(q{application/pdf; charset=utf-8});
		$openprint::r->headers_out->{'Content-Disposition'} = "attachment; filename=\"$file_base for docket $$Label{docket}.pdf\"";
				$variable{Download} = $content_pdf;
			} else {
				$openprint::log->debug("Error making pdf");
			} # end if has pdf contents
		} # end if successfully wrote html content

	} # end if
} # end sub label

sub _send_email {
	$variable{Label} = new openprint::Label($param{id});
} # end _send_email

1;
__END__
