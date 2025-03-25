use strict;
package openprint::Quote;
our @ISA=qw(openprint::Object);

use constant DEBUG => 0;

require MIME::QuotedPrint;
require HTML::Strip;

use openprint ();
use vars qw( $debug $r %variable $log $dbh %config %session $table $serial %fields %transforms %defaults %find_fields );
*variable = \%openprint::variable;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;
*session = \%openprint::session;
*r = \$openprint::r;

require sql;
require openprint::logs;
require openprint::QuotedProject;
require openprint::QuotedProduct;
require openprint::Currency;

$debug = 0;

$table = 'quotes';
$serial = 'quotes_id_seq';

%fields = (
	'id'			=>	'id',
	'created_on'	=>	'dtmquotedate',
	'updated_on'	=>	'dtmlastmodified',
	'company_id'	=>	'company_id',
  for_company_id  =>  'for_company_id',
	'user_id'		=>	'user_id',
	'currency_id'	=>	'currency_id',
	'status'		=>	'strstatus',
	'administrator_name'	=>	'stradministratorname',
	'administrator_comments'	=>	'stradministratorcomments',
	'customer_comments'		=>	'strcustomercomments',
	'modification1'	=>	'dblmodification1',
	'modification2'	=>	'dblmodification2',
	'modification3'	=>	'dblmodification3',
	'total1'		=>	'curtotalsale1',
	'total2'		=>	'curtotalsale2',
	'total3'		=>	'curtotalsale3',
	'Currency'		=>	undef,
	'reference'		=>	'reference',
	'comments'		=>	'comments',
	'deleted'		  =>	'deleted',
	'by_companyname'	=>	undef,
	'by_firstname'		=>	undef,
	'by_lastname'		=>	undef,
	'by_title'			=>	undef,
	'by_salutation'		=>	undef,
	'by_address1'		=>	undef,
	'by_address2'		=>	undef,
	'by_city'			=>	undef,
	'by_state'			=>	undef,
	'by_country'		=>	undef,
	'by_postalcode'		=>	undef,
	'by_phone'			=>	undef,
	'by_extension'		=>	undef,
	'by_fax'			=>	undef,
	'by_email'			=> undef,
	'for_companyname'	=>	undef,
	'for_firstname'		=>	undef,
	'for_lastname'		=>	undef,
	'for_title'			=>	undef,
	'for_salutation'		=>	undef,
	'for_address1'		=>	undef,
	'for_address2'		=>	undef,
	'for_city'			=>	undef,
	'for_state'			=>	undef,
	'for_country'		=>	undef,
	'for_postalcode'		=>	undef,
	'for_phone'			=>	undef,
	'for_extension'		=>	undef,
	'for_fax'			=>	undef,
	'for_email'			=> undef,
	);

%find_fields = (
	salesrep_id => '(SELECT salesrep_id FROM companies WHERE id=companyindex)',
	for_name	=> q{(SELECT strFirstName || ' ' || strLastName FROM tbl_Quote_Users_for WHERE quote_id=quotes.id)},
	project_id	=>	'(SELECT project_id FROM tbl_quote_details WHERE quote_id=id)',
);
%defaults = (
	'created_on'	=>	q`'NOW()'`,
	'updated_on'	=>	q`'NOW()'`,
	'currency_id'	=>	'openprint::Currency::get_current()->id()',
	'user_id'		=>	'$openprint::session{user_id}',
	'company_id'	=>	'$openprint::session{company_id}',
	'status'		=>	q`'Incomplete'`,
	'deleted'		=>	0,
);

sub load {
	my ( $self, $data ) = @_;
	if ( ! $data ) {
		$data = $dbh->selectrow_hashref( qq{SELECT * FROM $table WHERE id=?}, {}, $$self{id} );
	} # end if
	my @keys = map { defined $fields{$_} ? $_ : () } keys %fields;

	@$self{@keys} = @$data{@fields{@keys}};

	$data = $dbh->selectrow_hashref( q{SELECT * FROM tbl_Quote_Users_for WHERE quote_id=?}, {}, $$self{id} );
	@$self{qw/for_companyname for_firstname for_lastname for_title for_salutation for_address1 for_address2 for_city for_state for_country for_postalcode for_phone for_extension for_fax for_email/} = @$data{qw/strcompanyname strfirstname strlastname strtitle strsalutation straddress straddress2 strcity strstate strcountry strpostalcode strphone strextension strfax stremail/};

	$data = $dbh->selectrow_hashref( q{SELECT * FROM tbl_Quote_Users_by WHERE quote_id=?}, {}, $$self{id} );
	@$self{qw/by_companyname by_firstname by_lastname by_title by_salutation by_address1 by_address2 by_city by_state by_country by_postalcode by_phone by_extension by_fax by_email/} = @$data{qw/strcompanyname strfirstname strlastname strtitle strsalutation straddress straddress2 strcity strstate strcountry strpostalcode strphone strextension strfax stremail/};
} # end sub load

sub save {
	my ( $self, $params ) = @_;
	$self->set( $params ? $params : {} );
	my %sql;
	foreach my $key ( keys %fields ) {
		next if ! $fields{$key};
		$sql{$fields{$key}} = $$self{$key};
	} # end foreach
		
	my $ac = sql::start_transaction( $dbh );
	if ( ! $$self{id} ) {
		if ( $openprint::config{QuoteIDFormat} eq 'Year' ) {
			$dbh->do( "LOCK TABLE $table IN SHARE ROW EXCLUSIVE MODE" ) or $log->error( DBI->errstr );

			my ( $quote ) = sql::execute( undef, undef, q{SELECT MAX(id) FROM Quotes} );
			$quote =~ /(\d\d\d\d)/;
			if ( $1 > ( 1900 + (localtime(time))[5]) or $quote eq '' ) {
				return (1900 + (localtime(time))[5]) . '00001';
			} # end if
			$$self{id} = $quote + 1;
		} else {
			@$self{id} = sql::execute( undef, undef, q{SELECT nextval('quotes_id_seq')} );
		} # end if
		$sql{id} = $$self{id};
		if ( ( my $error = sql::insert( undef, undef, $table, \%sql ) ) ) {
			sql::end_transaction( $dbh, $ac );
			return $error;
		} # end if
		$openprint::Company->save({last_quote_id=>$$self{id}}) if $openprint::Company and $openprint::Company->id() and $$self{id};
	} else {
		my $error = sql::update( undef, undef, $table, ['id=?', $$self{id}], \%sql );
		if ( $error ) {
			sql::end_transaction( $dbh, $ac );
			return $error;
		} # end if
	} # end if
		sql::end_transaction( $dbh, $ac );
	$self->load();
	return;
} # end sub save

sub destroy {
	my $self = shift;

	if (!$$self{id}) {
		$log->error('Quote::delete called with no id');
		return;
	}

  my $error = '';
	my $ac = sql::start_transaction( $dbh );
	sql::execute( undef, undef, 'DELETE FROM tbl_Quote_Details WHERE quote_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM tbl_Quote_Users_By WHERE quote_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM tbl_Quote_Users_For WHERE quote_id=?', $$self{id} );
	sql::execute( undef, undef, 'DELETE FROM Quote_Log WHERE quote_id=?', $$self{id} );
  sql::execute( undef, undef, 'UPDATE Companies SET last_quote_id=NULL WHERE last_quote_id=?', $$self{id} );
  $error .= $self->SUPER::destroy();
	sql::end_transaction( $dbh, $ac );
  return $error;
} # end sub destroy

sub status {
	my ( $self, $new_status ) = @_;
	if ( defined $new_status and $$self{status} ne $new_status ) {
		#sql::update( $log, $dbh, 'Quotes', "Index=$$self{id}", 'strStatus', $new_status );
		$$self{status} = $new_status;
		#$self->add_log( "Changed Status to $new_status" );
	} # end if
	return $$self{status};
} # end sub status

sub add_log {
	my ( $self, $comment ) = @_;
	sql::insert( $log, $dbh, 'Quote_Log',
			'quote_id',		$$self{id},
			'company_id',	$session{company_id},
			'user_id',		$session{user_id},
			'Description',	$comment,
			);
} # end sub add_log

sub Quoted_Projects {
	if ( @_ > 1 ) {
		$_[0]{Quoted_Projects} = $_[1];
	} 
	if ( ! $_[0]{Quoted_Projects} ) {
		$_[0]{Quoted_Projects} = [ openprint::QuotedProject->find(quote_id=>$_[0]{id},order=>'project_id') ];
	} # end if
	return @{$_[0]{Quoted_Projects}};
} # end sub Quoted_Projects

sub Projects {
	my $self = shift;
	if ( ! exists $$self{Projects} ) {
		@{$$self{Projects}} = map { $_->Project() } $self->Quoted_Projects();
	} # end if
	return @{$$self{Projects}};
} # end sub projects

sub Products {
	my $self = shift;
	if ( ! exists $$self{Products} ) {
		$$self{Products} = [ openprint::QuotedProduct->find( quote_id=>$$self{id} ) ];
	} # end if
	return @{$$self{Products}};
} # end sub Products

sub for_name {
	my $self = shift;
	return $$self{for_firstname} . ' ' . $$self{for_lastname};
} # end sub
sub by_name {
	my $self = shift;
	return $$self{by_firstname} . ' ' . $$self{by_lastname};
} # end sub

sub contents {
	my $self = shift;
	$$self{contents} = $dbh->selectall_arrayref( q{SELECT * FROM tbl_Quote_Details WHERE quote_id=?}, {Slice=>{}}, $$self{id} );
	return $$self{contents};
}

sub markup1 {
	my $self = shift;
	my $project = shift;
	my $contents = $self->contents();
	my %hash = map { $_->{projectindex}, $_ } @$contents;
	if ( ref $project eq 'openprint::Project' ) {
		return $hash{$project->id()}{markup1};
	} else {
		return $hash{$project}{markup1};
	} # end if
}

sub store_user_by_info {
	my ( $self, $data ) = @_;

	my $ac = sql::start_transaction( $dbh );
	sql::execute( undef, undef, 'DELETE FROM tbl_Quote_Users_By WHERE quote_id=?', $$self{id} );
	sql::insert( undef, undef, 'tbl_Quote_Users_By',
			'quote_id',		$$self{id},
			'strFirstName',		$$data{ByFirstName},
			'strLastName',		$$data{ByLastName},
			'strCompanyName',	$$data{ByCompanyName},
			'strTitle',			$$data{ByTitle},
			'strSalutation',	$$data{BySalutation},
			'strAddress',		$$data{ByAddress1},
			'strAddress2',		$$data{ByAddress2},
			'strCity',			$$data{ByCity},
			'strState',			$$data{ByStateProvince},
			'strCountry',		$$data{ByCountry},
			'strPostalCode',	$$data{ByPostalCode},
			'strPhone',			$$data{ByPhone},
			'strExt',			$$data{ByExtension},
			'strFax',			$$data{ByFax},
			'strEmail',			$$data{ByEmail}
			);
	sql::end_transaction( $dbh, $ac );
	@$self{qw/by_companyname by_firstname by_lastname by_title by_salutation by_address1 by_address2 by_city by_state by_country by_postalcode by_phone by_extension by_fax by_email/} = 
		@$data{qw/ByCompanyName ByFirstName ByLastName ByTitle BySalutation ByAddress1 ByAddress2 ByCity ByState ByCountry ByPostalCode ByPhone ByExtension ByFax ByEmail/};

} # end sub store_user_by_info

sub store_user_for_info {
	my ( $self, $data ) = @_;

	my $ac = sql::start_transaction( $dbh );
	sql::execute( undef, undef, 'DELETE FROM tbl_Quote_Users_For WHERE quote_id=?', $$self{id} );
	sql::insert( undef, undef, 'tbl_Quote_Users_For',
			'quote_id',		$$self{id},
			'strFirstName',		$$data{ForFirstName},
			'strLastName',		$$data{ForLastName},
			'strCompanyName',	$$data{ForCompanyName},
			'strTitle',			$$data{ForTitle},
			'strSalutation',	$$data{ForSalutation},
			'strAddress',		$$data{ForAddress1},
			'strAddress2',		$$data{ForAddress2},
			'strCity',			$$data{ForCity},
			'strState',			$$data{ForStateProvince},
			'strCountry',		$$data{ForCountry},
			'strPostalCode',	$$data{ForPostalCode},
			'strPhone',			$$data{ForPhone},
			'strExt',			$$data{ForExtension},
			'strFax',			$$data{ForFax},
			'strEmail',			$$data{ForEmail}
		);
	sql::end_transaction( $dbh, $ac );
	@$self{qw/for_companyname for_firstname for_lastname for_title for_salutation for_address1 for_address2 for_city for_state for_country for_postalcode for_phone for_extension for_fax for_email/} = 
		@$data{qw/ForCompanyName ForFirstName ForLastName ForTitle ForSalutation ForAddress1 ForAddress2 ForCity ForState ForCountry ForPostalCode ForPhone ForExtension ForFax ForEmail/};
} # end sub store_for_info

sub description {
	if ( ! $_[0]{reference} ) {
	return join('<br/>', map { $_->reference() } $_[0]->Projects() );
	} else {
		return $_[0]{reference};
	} # end if
}

sub send {
	my $self = shift;
	my $results;

	my %quote;
	$quote{Quote} = $self;
	$quote{uri} = 'quote';
	openprint::quote::get_user_by_info( $log, $dbh, \%quote, $$self{id} );
	openprint::quote::get_user_for_info( $log, $dbh, \%quote, $$self{id} );
	openprint::quote::get_finished_quote_contents( $log, $dbh, \%quote, $$self{id} );
	my $email_template = ssi::slurp_content('/email_template.html');
  if (!$email_template) {
    $openprint::log->error('Have no email template!');
  }

	my $Email = new openprint::Email();

# Add a project summary for each project in the quote
	foreach my $Project ($self->Quoted_Projects()) {
		next if ! $Project->include_detailed();
		my %var;
		$var{Quote} = $self;
		$var{Project} = $Project->Project();
		$var{QuotedProject} = $Project;
		if ( $Project->template_id() ) {
			$var{ReplacementText} = join("\n",
					'<style type="text/css">',
					ssi::slurp_content('/css/project.css'),
					'</style>',
					ssi::slurp_content('/main/quote/_project_template_view.html')
					);
		} else {
			$variable{ReplacementText} = ssi::slurp_content('/email_content/project_view.html');
		} # end if
		$variable{ReplacementText} = ssi::variable_substitution( \$variable{ReplacementText}, \%var );
		$Email->add_pdf_attachment_from_html( sprintf('Project%d.html',$Project->project_id()), ssi::variable_substitution( \$email_template, \%variable ));
	} # for each Project

  my $from = sprintf('"%s %s" <%s>', @$self{'by_firstname','by_lastname','by_email'});
  if (index(lc $$self{by_email}, lc $openprint::config{domain}) == -1) {
    $from = $openprint::config{QuotingEmail};
  }

	if ( @_ ) {
		$quote{ReplacementText} = ssi::include( '/email_content/quote_end_user_body.html', \%quote );
		my $email_template = ssi::slurp_content( '/email_template.html' );
		$Email->html_body( ssi::variable_substitution( \$email_template, \%quote ) );

		$quote{ReplacementText} = ssi::include('/email_content/quote_end_user_invoice.html', \%quote );
    my $html = ssi::variable_substitution(\$email_template, \%quote);
		$Email->add_pdf_attachment_from_html("Quote$$self{id}",$html);
    if (($openprint::User->email() =~ /^isaac/) or ($openprint::User->email() =~ /^iconnor/) ) {
      $Email->add_html_attachment("Quote$$self{id}.html", $html);
    }

		$results .= $Email->send(
				FROM    => $from,
				TO      => @_,
				SUBJECT => "$openprint::config{SiteTitle}:Quote $$self{id}",
				);
		$Email->attachments(undef);
  } else {
    if ( $self->Company()->reseller() eq 'Y' or sets::isin( $session{user_type}, ['A', 'E']) ) {
      if ( $openprint::User->email_quotes_to_myself() and ($$self{by_email} eq $openprint::User->email())) {
        $quote{ReplacementText} = ssi::include( '/email_content/quote_reseller_by_body.html', \%quote );
        $Email->html_body( ssi::variable_substitution( \$email_template, \%quote ) );

        $quote{ReplacementText} = ssi::include( '/email_content/quote_reseller_by_invoice.html', \%quote );
        my $html = ssi::variable_substitution( \$email_template, \%quote );
        $Email->add_pdf_attachment_from_html( "Quote$$self{id}", $html );
        if ( ( $openprint::User->email() =~ /iconnor/ ) and @_ ) {
          $Email->add_html_attachment( "Quote$$self{id}.html", $html );
        }

        my $hs = $HTML::Strip->new();
        $results .= $Email->send(
            FROM    => $from,
            BCC		=>	'iconnor@connortechnology.com',
            TO      => sprintf('"%s %s" <%s>', @$self{'by_firstname','by_lastname','by_email'}),
            SUBJECT => sprintf('Quote %d for %s : ', $$self{id}, $self->for_companyname(), $hs->parse($self->reference())),
            );
        $Email->attachments(undef);
        $hs->eof;
      } # end if send_to_myself

      if ($$self{for_email} ne '') {
 #and ($quote{ForEmail} ne $openprint::User->email() ) and (
            #( $quote{ByFirstName} ne $quote{ForFirstName} ) or
            #( $quote{ByLastName} ne $quote{ForLastName} ) or
            #( $quote{ByCompanyName} ne $quote{ForCompanyName} ) or
            ##( $quote{ByTitle} ne $quote{ForTitle} ) or
            #( $quote{BySalutation} ne $quote{ForSalutation} ) or
            #( $quote{ByAddress1} ne $quote{ForAddress1} ) or
            #( $quote{ByAddress2} ne $quote{ForAddress2} ) or
            #( $quote{ByCity} ne $quote{ForCity} ) or
            ##( $quote{ByStateProvince} ne $quote{ForStateProvince} ) or
            #( $quote{ByCountry} ne $quote{ForCountry} ) or
            #( $quote{ByPostalCode} ne $quote{ForPostalCode} ) or
            #( $quote{ByPhone}  ne $quote{ForPhone} ) or
            #( $quote{ByExtension} ne $quote{ForExtension} ) or
            #( $quote{ByFax} ne $quote{ForFax} ) or
            #( $quote{ByEmail} ne $quote{ForEmail} )
            #) ) {
#
        openprint::quote::get_finished_quote_contents( $log, $dbh, \%quote, $$self{id} );

        my $For_User = openprint::User->find_one( email=>$$self{for_email} );
        $For_User = new openprint::User()->set({
            email     =>  $$self{for_email},
            firstname =>  $$self{for_firstname},
            lastname  =>  $$self{for_lastname},
            type=>'C'
            }) if ! $For_User;

        $quote{ReplacementText} = ssi::include( '/email_content/quote_reseller_for_body.html', \%quote );
        $Email->html_body( ssi::variable_substitution( \$email_template, \%quote ) );
        $quote{ReplacementText} = ssi::include( '/email_content/quote_reseller_for_invoice.html', \%quote );
        my $html = ssi::variable_substitution( \$email_template, \%quote );
        $Email->add_pdf_attachment_from_html( 'Quote'.$$self{id}, $html );
        if ( $For_User and sets::isin( $For_User->type(), [ 'E', 'A' ] ) ) {
          $Email->add_html_attachment('Quote'.$$self{id}.'.html', $html);
        } elsif ( scalar @_ and (
          ( $openprint::User->email() =~ /iconnor/ ) or
          ( $openprint::User->email() =~ /isaac/ ) 
        )
        ) {
          $Email->add_html_attachment( "Quote$$self{id}.html", $html );
        }

$log->debug("Sending to ".$For_User->email());
        $results .= $Email->send(
            FROM    => sprintf('"%s %s" <%s>', @$self{'by_firstname','by_lastname','by_email'}),
            BCC		=>	'iconnor@connortechnology.com',
            TO      => $For_User,
            SUBJECT => "Quote $$self{id} : " . $self->reference(),
            );
        $Email->attachments(undef);
      } # end if for email
      #} else {
        #$results .= 'Not sending to myself.<br/>';
      #} # end if for someone else
	} else {
# Not a reseller
    $openprint::log->debug("Not a reseller");
		$quote{ReplacementText} = ssi::include( '/email_content/quote_end_user_body.html', \%quote );
		my $email_template = ssi::slurp_content( '/email_template.html' );
		$Email->html_body( ssi::variable_substitution( \$email_template, \%quote ) );

		$quote{ReplacementText} = ssi::include('/email_content/quote_end_user_invoice.html', \%quote );
		$Email->add_pdf_attachment_from_html( "Quote$$self{id}", ssi::variable_substitution( \$email_template, \%quote ) );

		$results .= $Email->send(
				FROM    => $from,
				#TO    => sprintf('"%s %s" <%s>', @$self{'by_firstname','by_lastname','by_email'}),
        TO      => ( @_ ? $_[0] : sprintf('"%s %s" <%s>', @$self{'for_firstname','for_lastname','for_email'}) ),
        #TO		=>	'iconnor@connortechnology.com',
				SUBJECT => "$openprint::config{SiteTitle}:Quote $$self{id}",
				);
		$Email->attachments(undef);
	} # end if reseller or admin

		if ( $openprint::config{SendQuoteToAdmin} eq 'Y' ) {
			$log->debug("Sending quote to admin");
# Send one to the admin
			if ( $email_template ) {
				$quote{ReplacementText} = ssi::include( '/email_content/quote_admin_body.html', \%quote );
				$Email->html_body( ssi::variable_substitution( \$email_template, \%quote ) );

				openprint::quote::get_finished_quote_contents( $log, $dbh, \%quote, $$self{id} );
				$quote{ReplacementText} = ssi::include('/email_content/quote_admin_invoice.html', \%quote );
				$Email->add_pdf_attachment_from_html( "Quote$$self{id}", ssi::variable_substitution( \$email_template, \%quote ) );
				$results .= $Email->send(
						FROM    => $openprint::config{QuotingEmail},
						TO      => $openprint::config{QuotingEmail},
						SUBJECT => "$$self{for_companyname} : Quote $$self{id}",
						);
			} # end if
		} # end if

		my $send_due_to_custom_services = 0;
		foreach my $QuotedProject ($self->Quoted_Projects()) {
			my $Project = $QuotedProject->Project();
			my $services = $Project->services();
			if ( $$services{CustomService} and @{$$services{CustomService}} ) {
				foreach my $service_id ( @{$$services{CustomService}} ) {
					my $specs = openprint::service::get_specs_ref( $Project, $service_id );
					if ( map { $$specs{"txtPrice$_"} ? $$specs{"txtPrice$_"} : () } $Project->quantity_indexes() ) {
						$send_due_to_custom_services = 1;
						last;
					}
				}
				last if $send_due_to_custom_services;
			}
		} # end foreach Project
		if ( $send_due_to_custom_services ) {
			if ( $email_template ) {
				$quote{ReplacementText} = ssi::include( '/email_content/quote_admin_custom_body.html', \%quote );
				$Email->html_body( ssi::variable_substitution( \$email_template, \%quote ) );

				openprint::quote::get_finished_quote_contents( $log, $dbh, \%quote, $$self{id} );
				$quote{ReplacementText} = ssi::include('/email_content/quote_admin_invoice.html', \%quote );
				$Email->add_pdf_attachment_from_html( "Quote$$self{id}", ssi::variable_substitution( \$email_template, \%quote ) );
				$results .= $Email->send(
						FROM    => $openprint::config{QuotingEmail},
						TO      => $openprint::config{QuotingEmail},
						SUBJECT => "$$self{for_companyname} : Quote $$self{id} has custom modifications",
						);
			} # end if
		}
	} # end if ! @_

	$self->add_log( $results );
	return $results;
} # end sub send

sub total {
	my ( $self, $qty_index, $new_value ) = @_;
	if ( defined $new_value ) {
		$$self{'total'.$qty_index} = $new_value;
	} # end if
	return $$self{'total'.$qty_index};
} # end sub total

sub Currency {
	return new openprint::Currency( $_[0]{currency_id} );
} # end sub Currency

sub can_delete {
	my $User = $_[1] ? $_[1] : $openprint::User;
	if ( $$User{type} eq 'A' ) {
		return 1;
	} elsif ( $$User{id} == $_[0]{user_id} ) {
		return 1;
	} else {
		my $Company = $_[0]->Company();
		if ( $$Company{salesrep_id} = $$User{id} ) {
			return 1;
		} # end if
	} # end if
	return 0;
} # end sub can_delete

sub can_view {
	my $User = $_[1] ? $_[1] : $openprint::User;
	if ( $$User{type} eq 'A' ) {
		return 1;
	} elsif ( $$User{id} == $_[0]{user_id} ) {
		return 1;
	} elsif ( $$User{company_id} == $_[0]{company_id} ) {
		return 1;
	} else {
		my $Company = $_[0]->Company();
		if ( $$Company{salesrep_id} and sets::isin( $$Company{salesrep_id}, [ $$User{id}, $User->assistant_ids(), $User->csr_ids() ] ) ) {
			return 1;
		} # end if
		if ( openprint::usergroup::is_user_in( ['Accounting','SalesAdmin','Estimating'], $$User{id} ) ) {
			return 1;
		}
	} # end if
	return 0;
} # end sub can_view

sub can_send {
	my $User = $_[1] ? $_[1] : $openprint::User;
	if ( DEBUG ) {
		$openprint::log->debug("Quote->can_send user_type: $$User{type}, $_[0]{company_id} == $openprint::session{company_id}");
	}
	if ( sets::isin( $$User{type}, ['A','E'] ) or ( $_[0]{company_id} == $openprint::session{company_id} ) ) {
		return 1;
	} # end if
	return 0;
}
sub url_to {
	return '/main/quote/history_details.html?quote_id='.$_[0]{id};
} # end sub url_to

sub link_to {
	return sprintf('<a href="/main/quote/history_details.html?quote_id=%1$d">%2$s</a>', $_[0]{id}, ( $_[1] ? $_[1] : $_[0]{id} ) );
} # end sub link_to

sub For_Company() {
  if (!exists $_[0]{For_Company}) {
    $_[0]{For_Company} = new openprint::Company($_[0]{for_company_id});
  }
  return $_[0]{For_Company};
}

1;
__END__
