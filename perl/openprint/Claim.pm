use strict;
package openprint::Claim;
our @ISA = qw(openprint::Object);
require openprint::Object;


use openprint ();
use vars qw( $log $debug %fields %find_fields %transforms %defaults $table $serial );
*log = \$openprint::log;

require sql;
require ssi;
require misc;
require List::Util;
require Math::Round;

require openprint::Claim_Content;
require openprint::PurchaseOrder;
require openprint::Company;
require openprint::Currency;
require openprint::usergroup;
require openprint::Claim_Tax;
require openprint::Object_Asset;

$debug = 0;

$table = 'claims';
$serial = 'claims_id_seq';

%fields = (
	'id'			=>	'id',
	'company_id'	=>	'company_id',
	'created_on'	=>	'created_on',
	'created_by'	=>	'created_by',
	'updated_on'	=>	'updated_on',
	'filed_on'		=>	'filed_on',
	'sent_to_accounts_on'		=>	'sent_to_accounts_on',
	'invoiced_on'	=>	'invoiced_on',
	'cancelled_on'	=>	'cancelled_on',
	'invoice_id'	=>	'invoice_id',
	cancelled_on	=>	'cancelled_on',
	paid_on			=>	'paid_on',
	'po_id'			=>	'po_id',
	'docket'		=>	'docket',
	'supplier_id'	=>	'supplier_id',
	'contact_id'	=>	'contact_id',
	'currency_id'	=>	'currency_id',
	'total'				=>	'total',
	'subtotal'			=>	'subtotal',
	'deleted'			=>	'deleted',
	'reason'			=>	'reason',
	'vendor_contact'	=>	'vendor_contact',
	'vendor_name'		=>	'vendor_name',
	'vendor_address1'	=>	'vendor_address1',
	'vendor_address2'	=>	'vendor_address2',
	'vendor_city'		=>	'vendor_city',
	'vendor_country'	=>	'vendor_country',
	'vendor_state'		=>	'vendor_state',
	'vendor_postalcode'	=>	'vendor_postalcode',
	'vendor_phone'		=>	'vendor_phone',
	'vendor_fax'		=>	'vendor_fax',
	'vendor_sms'		=>	'vendor_sms',
	'vendor_email'		=>	'vendor_email',
	'editor_id'			=>	'editor_id',
	'also_notify'		=>	'also_notify',
);

%find_fields = (
);

%transforms = (
	'updated_on'	=> [ 's/.*//g' ],
	'po_id'			=>	[ 's/\D//g' ],
	'supplier_id'	=>	[ 's/\D//g' ],
	'contact_id'	=>	[ 's/\D//g' ],
	'currency_id'	=>	[ 's/\D//g' ],
);

%defaults = (
	'created_on'	=>	q`'NOW()'`,
	'updated_on'	=>	q`'NOW()'`,
	'filed_on'	=>	undef,
	'sent_to_accounts_on'	=>	undef,
	'invoiced_on'	=>	undef,
	cancelled_on	=>	undef,
	paid_on			=>	undef,
	'po_id'			=>	undef,
	'docket'		=>	undef,
	'supplier_id'	=>	undef,
	'contact_id'	=>	undef,
	'invoice_id'	=>	undef,
	'currency_id'	=>	undef,
	'total'			=>	0,
	'subtotal'		=>	0,
	'deleted'		=>	0,
	'editor_id'		=>	'[]',
);

sub save {
	my ( $self, $hash ) = @_;
	$self->subtotal(undef);
	foreach my $Tax ( $self->Taxes() ) {
		$Tax->amount(undef);
	} # end foreach Tax
	$self->total(undef);
	if ( ! $$hash{'currency_id'} ) {
		my $Currency = openprint::Currency::get_current();
		$$hash{'currency_id'} = $Currency->id();
	} # end if
	$$self{'created_by'} = $openprint::session{'user_id'} if ! $$self{'created_by'};
	$$self{'company_id'} = $openprint::session{'company_id'} if ! $$self{'company_id'};
	my $error = $self->SUPER::save( $hash );
	if ( ! $error ) {
		# Taxes
		foreach my $T ( $self->Taxes() ) {
			$error .= $T->save();
		} # end foreach
	} # end if
	return $error;
} # end sub save

sub destroy {
    my $self = shift;
    my $ac = sql::start_transaction( );
    sql::execute( undef, undef, q{DELETE FROM Claim_Taxes WHERE claim_id=?}, $$self{'id'} );
    sql::execute( undef, undef, q{DELETE FROM Claim_Contents WHERE claim_id=?}, $$self{'id'} );
	return $openprint::dbh->errstr() if $openprint::dbh->errstr();
    sql::execute( undef, undef, q{DELETE FROM Claims WHERE id=?}, $$self{'id'} );
    sql::end_transaction( undef, $ac );
	return $openprint::dbh->errstr() if $openprint::dbh->errstr();
	delete $openprint::Object::cache{'openprint::Claim'}{$$self{'id'}};
	return '';
} # end sub delete

sub Contents {
	my ( $self, %params ) = @_;
	if ( %params ) {
		if ( $$self{'id'} ) {
			return openprint::Claim_Content->find('claim_id'=>$$self{id}, %params );
		} # end if
	} # end if
	if ( ! $$self{'Contents'} ) {
		if ( $$self{'id'} ) {
			$$self{'Contents'} = [ openprint::Claim_Content->find( claim_id=>$$self{id} ) ];
		} # end if
	} # end if
	return @{$$self{'Contents'}} if $$self{'Contents'};
	return;
} # end sub Contents

sub Vendor {
	return new openprint::Company( $_[0]{'supplier_id'} );
} # end sub Vendor

sub Currency {
	return new openprint::Currency( $_[0]{'currency_id'} );
} # end sub Currency

sub Creator {
	return new openprint::User( $_[0]{created_by} );
} # end sub Creator

sub subtotal {
	my ( $self, $new ) = @_;
	
	$$self{'subtotal'} = $_[1] if ( @_ > 1 );
	if ( ! $$self{'subtotal'} ) {
		$$self{'subtotal'} = 0;
		foreach my $C ( $self->Contents() ) {
			$$self{'subtotal'} += $C->total();
		} # end foreach
        $$self{'subtotal'} = Math::Round::nearest( 0.01, $$self{'subtotal'} );
	} # endif
	return $$self{'subtotal'};
} # end sub subtotal

sub total {
	my ( $self ) = @_;
	$$self{'total'} = $_[1] if ( @_ > 1 );
	if ( ! $$self{'total'} ) {
		$$self{'total'} = $self->subtotal();
        foreach my $Tax ( $self->Taxes() ) {
            $$self{'total'} += $Tax->amount();
        } # end foreach Tax
        $$self{'total'} = Math::Round::nearest( 0.01, $$self{'total'} );
	} # end if
	return $$self{'total'};
} # end sub total

sub Contact {
	return new openprint::User( $_[0]{'contact_id'} );
} # end sub Contact

sub send {
require MIME::Base64;
require MIME::QuotedPrint;
	my ( $self, @To ) = @_;

	my $From = new openprint::User( $openprint::session{'user_id'} );
	
	my %info = (
			Claim	=>	$self,
			From	=>	$From,
			);
	my @attachments = ();

	my $email_template = misc::load_file( $log, $openprint::config{'SkinPath'} . '/email_template.html' );
	$info{'ReplacementText'} = ssi::include( '/email_content/claim_body.html', \%info );
	$_ = MIME::QuotedPrint::encode_qp( Encode::encode('utf-8', ssi::variable_substitution( \$email_template, \%info ) ) );
	push @attachments, ('', $_, 'text/html', 'quoted-printable');

	my $content = ssi::include( '/email_content/claim.html', \%info );
	push @attachments, $From->Company()->name().'-CLAIM'.$$self{'id'}.'.html', MIME::QuotedPrint::encode_qp( Encode::encode('utf-8',$content) ), 'text/html', 'quoted-printable';

	if ( 0 and $self->include_attachments() ) {
		require MIME::Types;
		my $types = MIME::Types->new;
		foreach my $Claim_Asset ( $self->Assets() ) {
			my $Asset = $Claim_Asset->Asset();
			push @attachments, $Asset->filename(), 
				 MIME::Base64::encode_base64( misc::load_file( $log, $Asset->on_disk_path() ) ), 
				 $types->mimeTypeOf($Asset->filename()), 'base64';
		} # end foreach Asset
	} # end if

	my $results = 'CLAIM ' . $$self{'id'} . ' emailed to the following recipients:<br/>';
	my $Email = new openprint::Email();
	$results .= $Email->send( 
			TO	=>	( @To ? \@To : ( ($self->Contact()->email() ? $self->Contact() : sprintf('<%s> "%s"', @$self{'vendor_contact','vendor_email'})) ) ),
			BCC	=>	sprintf( '"%s" <%s>', $From->name(), $From->email() ),
			#TO	=>	$From,
			FROM	=>	$From,
			SUBJECT	=>	'CLAIM ' . $self->id() . ' for ' . $self->Vendor()->name(),
			ATTACHMENTS =>	\@attachments,
			);
	return $results;
} # end sub send

sub Taxes {
    my ( $self ) = @_;

	return if ! ( $$self{'id'} and $$self{'supplier_id'} );

    if ( ! $$self{'Taxes'} ) {
        @{$$self{'Taxes'}} = openprint::Claim_Tax->find('claim_id'=>$$self{'id'});
    } # end if
    if ( ! @{$$self{'Taxes'}} ) {
        foreach my $Tax ( openprint::Tax->find(
                    'period_start null_or_<='   =>  $$self{'created_on'},
                    'period_end null_or_>='     =>  $$self{'created_on'},
                    'country'   =>  $self->Company()->country(),
                    'state'     =>  $self->Company()->state()),
                ) {
            my $T = new openprint::Claim_Tax();
            $T->save({
                'claim_id'=>  $$self{'id'},
                'tax_id'    =>  $$Tax{'id'},
                'rate'      =>  $$Tax{'rate'},
            });
            push @{$$self{'Taxes'}}, $T;
        } # end foreach Tax
    } # end if
    return @{$$self{'Taxes'}};
} # end sub Taxes

sub Tax {
    my $result = openprint::Claim_Tax->find_one('claim_id'=>$_[0]{'id'}, 'tax_id'=>$_[1]->id() );
    if ( ! $result ) {
        return new openprint::Claim_Tax();
    } # end if
    return $result;
} # end sub Tax

sub Assets {
	return () if ! $_[0]{'id'};
	my ( $self, %param ) = @_;
	$param{object_id} = $_[0]{id};
	$param{object_type} = 'openprint::Claim';
	$param{order}	=	'asset_id' if ! $param{'order'};
	my @Assets = openprint::Object_Asset->find(%param);	
	return @Assets;
} # end sub Assets

sub Payments {
	return () if ! $_[0]{'id'};
	my ( $self, %param ) = @_;
	$param{'claim_id'} = $_[0]{'id'};
	$param{'order'}	=	'payment_id' if ! $param{'order'};
	my @Payments = openprint::Claim_Payment->find(%param);	
	return @Payments;
} # end sub Payments

sub paid {
	if ( @_ > 1 ) {
		$_[0]{paid} = $_[1];
	} # end if
	if ( ! $_[0]{paid} ) {
		$_[0]{paid} = List::Util::sum( map { $_->amount() } $_[0]->Payments() );
	} # endif
	return $_[0]{paid};
} # end sub paid

sub owing {
	return $_[0]->total() - $_[0]->paid();
} # end sub owing

sub can_view {
	return 1 if ! $_[0]{id};
	return 1 if $openprint::session{user_id} == $_[0]->created_by();
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if openprint::usergroup::is_user_in( ['Accounting','SalesAdmin','Sales'], $openprint::session{'user_id'} );
	return 0;
} # end sub can_view

sub can_view_pricing {
	return 1 if ! $_[0]{id};
	return 1 if $openprint::session{user_id} == $_[0]->created_by();
	return 1 if $openprint::session{user_type} eq 'A';
	return 1 if openprint::usergroup::is_user_in( ['Accounting','SalesAdmin','Sales'], $openprint::session{'user_id'} );
	return 0;
} # end sub can_viww_pricieng
1;
__END__
