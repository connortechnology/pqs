use strict;
use warnings;
package openprint::Paper;
our @ISA = qw(openprint::Object);
require openprint::Object;
use Carp qw( cluck );
require Math::Round;
require POSIX;

use openprint ();
use vars qw( $log %variable %config );
*variable = \%openprint::variable;
*config = \%openprint::config;
*log = \$openprint::log;

require sql;
require misc;
require openprint::Company;
#require openprint::Manufacturer;
require openprint::PaperPrice;
#require openprint::Skid;
#require openprint::SkidContent;
require openprint::StockBrand;
require openprint::StockFinish;
require openprint::StockColour;
require openprint::StockWeight;
require openprint::StockQuality;
require openprint::StockGroup;
require openprint::StockMaterial;
#require openprint::Equipment_Stock_Setting;
#require openprint::PaperInventory;
require openprint::PaperRecommendation;

use Time::HiRes qw{ time gettimeofday tv_interval }; 

use vars qw( $debug $table $serial %fields %find_fields %defaults %transforms %grades $default_sort );

use constant DEBUG_PRICING => 0;
use constant DEBUG => 0;

$debug = 1;
$table = 'tbl_paper';
$serial	= 'paper_id_seq';
%fields = (
		id				=>	'lngindex', 
    name      =>    'strid',
    created_on		=>	'created_on',
    group_id		=>	'group_id',
    owner_id		=>	'owner_id',
    supplier_id		=>	'supplier_id',
    manufacturer_id	=>	'manufacturer_id',
		brand_id		=>	'brand_id',
    brand       =>  'strname',
		colour_id		=>	'colour_id',
    colour      => 'strcolour',
		finish_id		=>	'finish_id',
    finish      => 'strfinish',
		weight_id		=>	'weight_id',
    weight      => 'strweight',,
    quality_id		=>	'quality_id',
		calliper		=>	'strcalliper',
    #taxexempt1		=>	'ysntaxexempt1',
    #taxexempt2		=>	'ysntaxexempt2',
    cuttable		=>	'cut_paper', 
		multipart		=>	'multipart', 
    doublesided		=>	'ysndoublesided', 
    c1sc2s => 'c1sc2s',
    perfecting		=>	'ysnperfecting', 
    score_required	=>	'score_required',
    die_score_required	=>	'die_score_required',
		width				=>	'dblwidth',
		height			=>	'dblheight',
		mweight			=>	'strmweight',
    sheets_per_package	=>	'sheets_per_package',
    gsm					=>	'gsm',
    wpsi				=>	'wpsi',
    digital				=>	'digital',
    type				=>	'type',
		basis_width			=>	'basis_width',
		basis_height		=>	'basis_height',
		basis_mweight		=>	'basis_mweight',
    bladecleaning		=>	'bladecleaning',
    grade				=>	'grade',
    grain_direction		=>	'grain_direction',
    fsc_code			=>	'fsc_code',
    supplied			=>	'supplied',
    minimum_order		=>	'minimum_order',
    inventory_number	=>	'inventory_number',
    full_packages		=>	'full_packages',
    message				=>	'message',
    in_stock			=>	'in_stock',
    allocated			=>	'allocated',
    parts				=>	'lngmultipart',
    material_id			=>	'material_id',
    user_type			=>	'user_type',
    available_to_order	=>	'available_to_order',
    #department_id		=>	'department_id',
    Supplied			=>	undef,
		);
%find_fields = (
		#manufacturer	=>	'(SELECT name FROM manufacturers WHERE manufacturers.id=papers.manufacturer_id)',
		manufacturer	=>	'manufacturer_id = (SELECT id FROM manufacturers WHERE name=?)',
		#group	=>	'(SELECT name FROM stockgroups WHERE stockgroups.id=papers.group_id)',
		group	=>	'group_id = (SELECT id FROM stockgroups WHERE name=?)',
		#material	=>	'(SELECT name FROM stockmaterials WHERE stockmaterials.id=papers.material_id)',
		material	=>	'material_id = (SELECT id FROM stockmaterials WHERE name=?)',
		#brand	=>	'(SELECT name FROM stockbrands WHERE stockbrands.id=papers.brand_id)',
		brand	=>	'brand_id = (SELECT id FROM stockbrands WHERE name=?)',
		#finish	=>	'(SELECT name FROM stockfinishes WHERE stockfinishes.id=papers.finish_id)',
		finish	=>	'finish_id = (SELECT id FROM stockfinishes WHERE name=?)',
		#colour	=>	'(SELECT name FROM stockcolours WHERE stockcolours.id=papers.colour_id)',
		colour	=>	'colour_id = (SELECT id FROM stockcolours WHERE name=?)',
		#weight	=>	'(SELECT name FROM stockweights WHERE stockweights.id=papers.weight_id)',
		weight	=>	'weight_id = (SELECT id FROM stockweights WHERE name=?)',
		#quality	=>	'(SELECT name FROM stockqualities WHERE stockqualities.id=papers.quality_id)',
		quality	=>	'quality_id = (SELECT id FROM stockqualities WHERE name=?)',
		size		=>	q`width || '" x ' || height || '"'`,
		sheetsize		=>	q`width || '" x ' || height || '"'`,
		allocated_to_docket	=>	'(SELECT docket FROM paper_allocations WHERE paper_id = tbl_paper.lngindex)',
		project_type_name	=>	'(SELECT name FROM project_types WHERE id IN ( SELECT lngProjectTypeIndex FROM tbl_Paper_Recommendations WHERE lngPaperIndex = tbl_paper.lngindex ) )',
		project_type_id		=>	'(SELECT lngProjectTypeIndex FROM tbl_Paper_Recommendations WHERE lngPaperIndex = tbl_paper.lngindex)',
		stock_settings_equipment_id	=>	'(SELECT equipment_id FROM equipment_stock_settings WHERE stock_id=tbl_paper.lngindex)',
		);

$default_sort = join(',', map { $fields{$_} } qw(brand finish colour weight width height));

%transforms = (
	id			=>	[ 's/\D//g', '<2147483647' ],
	manufacturers_name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+$/ /g' ],
	gsm				=>	 [ 's/[^\d\.]//g' ],
	wpsi				=>	 [ 's/[^\d\.\-eE]//g' ],
	calliper		=>	 [ 's/[^\d\.]//g' ],
	basis_mweight	=>	 [ 's/[^\d\.]//g' ],
	mweight			=>	 [ 's/[^\d\.]//g' ],
	fsc_code		=> [ 's/^\s+//', 's/\s+$//', 's/\s\s+$/ /g' ],
);

%defaults = (
	created_on	=>	q`'NOW()'`,
	group_id			=>	undef,
	owner_id			=>	undef,
	supplier_id			=>	undef,
	manufacturer_id		=>	undef,
	brand_id			=>	undef,
	finish_id			=>	undef,
	colour_id			=>	undef,
	weight_id			=>	undef,
	quality_id			=>	undef,
	material_id			=>	undef,
	calliper	=>	undef,
	taxexempt1		=>	q`'0'`,
	taxexempt2		=>	q`'0'`,
	cuttable		=>	q`'1'`,
	multipart	=>	q`'0'`,
	doublesided		=>	q`'Y'`,
	perfecting		=>	q`'N'`,
	score_required	=>	q`'0'`,
	die_score_required	=>	q`'0'`,
	width		=>	undef,
	height		=>	undef,
	mweight		=>	undef,

	basis_width	=>	undef,
	basis_height	=>	undef,
	basis_mweight	=>	undef,
	gsm			=>	undef,	
	grade		=>	undef,
	allocated	=>	q`'0'`,
	in_stock	=>	q`'0'`,
	bladecleaning	=>	q`'0'`,
	#user_type	=>	q`''`,
	user_type	=>	undef,
	supplied		=>	undef,
	sheets_per_package	=>	undef,
	wpsi				=>	undef,
	type				=>	q`'Sheet'`,
	available_to_order	=>	undef,
	department_id		=>	undef,
	inventory_number	=>	undef,
	full_packages		=>	q`'0'`,
	minimum_order		=>	q`'0'`,
	parts				=>	undef,
	digital				=>	q`'0'`,
	message				=>	undef,
	fsc_code			=>	undef,
);

%grades = (
		1	=>	'1 Gloss-coated stock',
		2	=>	'2 Matte-coated stock',
		3	=>	'3 Gloss-coated, web stock', 
		4	=>	'4 Uncoated, white stock', 
		5	=>	'5 Uncoated, yellow stock'
);

sub new {
  my $self = openprint::Object::new(@_);
	@$self{'start_width','start_height','Supplied'} = ( @$self{'width','height'}, $self );
  return $self;
}

sub load {
	my ( $self, $data ) = @_;
	if ( ! $data ) {
		$data = $openprint::dbh->selectrow_hashref( 'SELECT * FROM '.$table.' WHERE '.$fields{id}.'=?', {}, $$self{id} );
	} # end if
	my @keys = map { (defined $fields{$_}) ? $_ : () } keys %fields;
	@$self{@keys} = @$data{@fields{@keys}};
	if ( exists $$data{allocated} ) {
		$$self{allocated} = $$data{allocated}
	}
	@$self{'start_width','start_height','Supplied'} = ( @$self{'width','height'}, $self );
} # end sub load

# Returns a copy of the paper object.
sub copy {
  my $self = shift;
	my $new = $self->clone();
	$$new{id} = '';
	delete $$new{created_on};
	$$new{name} = 'Copy of '.$$self{name};
  my $copy = 1;
  while (my @result = sql::execute(undef, undef, 'SELECT '.$fields{id}.' FROM '.$table.' WHERE '.$fields{name}.'=? LIMIT 1', $$new{name})) {
    $$new{name} = 'Copy '.$copy. ' of '.$$new{name};
    $copy ++;
  }
  $$new{Prices} = [ map { $_->paper_id(undef); $_ } $self->Prices() ];
  $$new{Recommendations} = [ map { $_->paper_id(undef); $_; } $self->Recommendations() ];
	return $new;
} # end sub copy

sub Prices {
	if ( @_ > 1 ) {
		$_[0]{Prices} = $_[1];
	} # end if
	if ( ! $_[0]{Prices} ) {
		$_[0]{Prices} = [ openprint::PaperPrice->find( paper_id => $_[0]{id} ) ] if $_[0]{id};
	} # end if
	return @{$_[0]{Prices}} if $_[0]{Prices};
	return ();
} # end sub Prices

sub save {
	my ( $self, $hash ) = @_;

	$self->set($hash ? $hash : {});
	
	if ( $$self{group} and ! $$self{group_id} ) {
		my $Group = openprint::StockGroup->find_one('name lc'=>lc openprint::StockGroup->transform( 'name', $$self{group} ) );
		if ( ! $Group ) {
			$Group = new openprint::StockGroup();
			if ( $_ = $Group->save( { name=>$$self{group} } ) ) {
				return $_;
			} # end if
		} # end if
		if ( ! $Group ) {
			return "Something odd happened saving the group. $$self{group}<br/>";
		} # end if
		@$self{'group_id','group'} = @$Group{'id','name'};
	} # end if group_id

	if ( $$self{material} and ! $$self{material_id} ) {
		my $Material = openprint::StockMaterial->find_one('name lc'=>lc openprint::StockMaterial->transform( 'name', $$self{material} ) );
		if ( ! $Material ) {
			$Material = new openprint::StockMaterial();
			if ( $_ = $Material->save( {name=>$$self{material}} ) ) {
				return $_;
			} # end if
		} # end if
		@$self{'material_id','material'} = @$Material{'id','name'};
	} # end if material

	if ( $$self{brand} and ! $$self{brand_id} ) {
		my $Brand = openprint::StockBrand->find_one('name lc'=>lc openprint::StockBrand->transform( 'name', $$self{brand} ) );
		if ( ! $Brand ) {
			$Brand = new openprint::StockBrand();
			if ( $_ = $Brand->save({name=>$$self{brand}}) ) {
				return $_;
			} # end if
		} # end if
		@$self{'brand_id','brand'} = @$Brand{'id','name'};
	} # end if brand_id

	if ( $$self{finish} and ! $$self{finish_id} ) {
		my $Finish = openprint::StockFinish->find_one('name lc'=>lc openprint::StockFinish->transform( 'name', $$self{finish} ) );
		if ( ! $Finish ) {
			$Finish = new openprint::StockFinish();
			if ( $_ = $Finish->save({name=>$$self{finish}}) ) {
				return $_;
			} # end if
		} # end if
		@$self{'finish_id','finish'} = @$Finish{'id','name'};
	} # end if finish_id

	if ( $$self{colour} and ! $$self{colour_id} ) {
		my $Colour = openprint::StockColour->find_one('name lc'=>lc openprint::StockColour->transform( 'name', $$self{colour} ) );
		if ( ! $Colour ) {
			$Colour = new openprint::StockColour();
			if ( $_ = $Colour->save({name=>$$self{colour}}) ) {
				return $_;
			} # end if
		} # end if
		@$self{'colour_id','colour'} = @$Colour{'id','name'};
	} # end if colour_id

	if ( $$self{weight} and ! $$self{weight_id} ) {
		my $Weight = openprint::StockWeight->find_one('name lc'=>lc openprint::StockWeight->transform( 'name', $$self{weight} ) );
		if ( ! $Weight ) {
			$Weight = new openprint::StockWeight();
			if ( $_ = $Weight->save({ name=>$$self{weight}}) ) {
				return $_;
			} # end if
		} # end if
		@$self{'weight_id','weight'} = @$Weight{'id','name'};
	} # end if weight_id

	if ( $$self{quality} and ! $$self{quality_id} ) {
		$$self{quality} = openprint::StockQuality->transform( 'name', $$self{quality} );
		my $Quality = openprint::StockQuality->find_one('name lc'=>lc $$self{quality});
		if ( ! $Quality ) {
			$Quality = new openprint::StockQuality();
			if ( $_ = $Quality->save({name=>$$self{quality}}) ) {
				return $_;
			} # end if
		} # end if
		@$self{'quality_id','quality'} = @$Quality{'id','name'};
	} # end if quality_id
	if ( $$self{manufacturer} and ! $$self{manufacturer_id} ) {
		my $Manufacturer = openprint::Manufacturer->find_one('name lc'=>lc openprint::Manufacturer->transform( 'name', $$self{manufacturer} ) );
		if ( ! $Manufacturer ) {
			$Manufacturer = new openprint::Manufacturer();
			if ( $_ = $Manufacturer->save({name=>$$self{manufacturer}}) ) {
				return $_;
			} # end if
		} # end if
		@$self{'manufacturer_id','manufacturer'} = @$Manufacturer{'id','name'};
	} # end if manufacturer

	if ( $$self{id} ) {
		$self->in_stock(undef);
		$self->allocated(undef,undef);
	} # end if

	$$self{height} = undef if $$self{type} eq 'Roll';
	
	my $error;
	#$error .= 'An owner must be selected.<br/>' if ! $$self{owner_id};
	# Why?
	#$error .= 'A manufacturer must be selected.<br/>' if ! $$self{manufacturer_id};

	return $error if $error;

	my $ac = sql::start_transaction( $openprint::dbh );
	$error = $self->SUPER::save();
	if ( $error ) {
		$openprint::dbh->rollback();
		sql::end_transaction( $openprint::dbh, $ac );
		return $error;
	} # end if
	sql::execute( undef, undef, 'DELETE FROM StockBrands WHERE id NOT IN (SELECT DISTINCT brand_id FROM '.$openprint::Paper::table.')' );
	sql::execute( undef, undef, 'DELETE FROM StockFinishes WHERE id NOT IN (SELECT DISTINCT finish_id FROM '.$openprint::Paper::table.')' );
	sql::execute( undef, undef, 'DELETE FROM StockColours WHERE id NOT IN (SELECT DISTINCT colour_id FROM '.$openprint::Paper::table.')' );
	sql::execute( undef, undef, 'DELETE FROM StockWeights WHERE id NOT IN (SELECT DISTINCT weight_id FROM '.$openprint::Paper::table.')' );
	sql::execute( undef, undef, 'DELETE FROM StockGroups WHERE id NOT IN (SELECT DISTINCT group_id FROM '.$openprint::Paper::table.')' );
	sql::execute( undef, undef, 'DELETE FROM StockMaterials WHERE id NOT IN (SELECT DISTINCT material_id FROM '.$openprint::Paper::table.')' );
	sql::execute( undef, undef, 'DELETE FROM StockQualities WHERE id NOT IN (SELECT DISTINCT quality_id FROM '.$openprint::Paper::table.')' );

	my @Recommendations = $self->Recommendations();
  my @ids = map {$$_{id} ? $$_{id} : ()} @Recommendations;
	sql::execute( undef, undef, 'DELETE FROM '.$openprint::PaperRecommendation::table.' WHERE '.$openprint::PaperRecommendation::fields{paper_id}.'=? and id NOT IN ('.join(',', map { '?' } @ids).')', $$self{id}, @ids ) if @ids;
	foreach my $rec ( @Recommendations ) {
		if ( $$rec{paper_id} != $$self{id} ) {
			$$rec{paper_id} = $$self{id};
			$$rec{id} = undef;
		} # end if
    $rec->save();
    if ( $openprint::dbh->errstr() ) {
      $openprint::dbh->rollback();
      sql::end_transaction( $openprint::dbh, $ac );
      return $openprint::dbh->errstr();
    } # end if
	} # end foreach

	foreach my $Price ( $self->Prices() ) {
		if ( $$Price{paper_id} != $$self{id} ) {
			$$Price{paper_id} = $$self{id};
			$$Price{id} = undef;
		} # end if
		$Price->save();
	} # end foreach

	sql::end_transaction( $openprint::dbh, $ac );
	return;
} # end sub save

sub merge {
	my ( $self, $Duplicate ) = @_;
	my $ac = sql::start_transaction( $openprint::dbh );
	sql::update( undef, undef, 'Paper_allocations', [ 'paper_id=?', $Duplicate->id() ], 'paper_id', $self->id() );
  #sql::update( undef, undef, 'Paper_Inventory', [ 'paper_id=?', $Duplicate->id() ], 'paper_id', $self->id() );
	sql::update( undef, undef, 'skid_contents', [ 'paper_id=?', $Duplicate->id() ], 'paper_id', $self->id() );
	sql::update( undef, undef, 'tbl_paper_prices', [ 'lngpaperindex=?', $Duplicate->id() ], 'lngpaperindex', $self->id() );
	sql::update( undef, undef, 'tbl_paper_recommendations', [ 'lngpaperindex=?', $Duplicate->id() ], 'lngpaperindex', $self->id() );
  #sql::update( undef, undef, 'manifest_content_types', [ 'paper_id=?', $Duplicate->id() ], 'paper_id', $self->id() );
	$Duplicate->delete();
	$self->save({in_stock=>undef});
	sql::end_transaction( $openprint::dbh, $ac );
} # end sub merge

sub delete {
	my $self = shift;

	my $error;

	my $ac = sql::start_transaction( );
	# We don't want to lose the paper if it's in a manifest
	#sql::update( undef, undef, 'manifest_content_types', ['paper_id=?', $$self{id}], 'paper_id', undef );
	sql::execute( undef, undef, q{DELETE FROM Paper_Allocations WHERE paper_id=?}, $$self{id} );
	$error .= $openprint::dbh->errstr();
  #sql::execute( undef, undef, q{DELETE FROM Paper_Inventory WHERE paper_id=?}, $$self{id} );
  #$error .= $openprint::dbh->errstr();
	sql::execute( undef, undef, q{DELETE FROM tbl_paper_prices WHERE lngpaperindex=?}, $$self{id} );
	$error .= $openprint::dbh->errstr();
	sql::execute( undef, undef, q{DELETE FROM tbl_paper_recommendations WHERE lngpaperindex=?}, $$self{id} );
	$error .= $openprint::dbh->errstr();
	sql::execute( undef, undef, q{DELETE FROM Skid_Contents WHERE paper_id=?}, $$self{id} );
	$error .= $openprint::dbh->errstr();
  #sql::execute( undef, undef, q{DELETE FROM inventory_check_entries WHERE paper_id=?}, $$self{id} );
  #$error .= $openprint::dbh->errstr();
  #sql::execute( undef, undef, q{UPDATE manifest_content_types SET paper_id=NULL WHERE paper_id=?}, $$self{id});
  #$error .= $openprint::dbh->errstr();
  #foreach my $ESS ( openprint::Equipment_Stock_Setting->find( stock_id=>$$self{id} ) ) {
  #$ESS->destroy();
  #} # end foreach
  #$error .= $openprint::dbh->errstr();
	sql::execute( undef, undef, 'DELETE FROM '.$table.' WHERE '.$fields{id}.'=?', $$self{id} );
	$error .= $openprint::dbh->errstr();

	if ( ! sql::execute( undef, undef, 'SELECT DISTINCT brand_id FROM '.$table.' WHERE brand_id=?', $$self{brand_id} ) ) {
		sql::execute( undef, undef, q{DELETE FROM StockBrands WHERE id=?}, $$self{brand_id} );
	$error .= $openprint::dbh->errstr();
	} # end if
	if ( ! sql::execute( undef, undef, 'SELECT DISTINCT finish_id FROM '.$table.' WHERE finish_id=?', $$self{finish_id} ) ) {
		sql::execute( undef, undef, q{DELETE FROM StockFinishes WHERE Id=?}, $$self{finish_id} );
	$error .= $openprint::dbh->errstr();
	} # end if
	if ( ! sql::execute( undef, undef, 'SELECT DISTINCT colour_id FROM '.$table.' WHERE colour_id=?', $$self{colour_id} ) ) {
		sql::execute( undef, undef, q{DELETE FROM StockColours WHERE Id=?}, $$self{colour_id} );
	$error .= $openprint::dbh->errstr();
	} # end if
	if ( ! sql::execute( undef, undef, 'SELECT DISTINCT weight_id FROM '.$table.' WHERE weight_id=?', $$self{weight_id} ) ) {
		sql::execute( undef, undef, q{DELETE FROM StockWeights WHERE Id=?}, $$self{weight_id} );
	$error .= $openprint::dbh->errstr();
	} # end if
	sql::execute( undef, undef, 'DELETE FROM StockGroups WHERE id NOT IN (SELECT DISTINCT group_id FROM '.$table.')' );
	$error .= $openprint::dbh->errstr();
	sql::execute( undef, undef, 'DELETE FROM StockMaterials WHERE id NOT IN (SELECT DISTINCT material_id FROM '.$table.')' );
	$error .= $openprint::dbh->errstr();
	
	# Add record to audit log - action "Delete Paper".
	new openprint::Log()->save({action=>'Delete Paper', note=>'Stock ID: '.$$self{id}  . $self->to_string() });
	sql::end_transaction( undef, $ac );
	
	return $error;
} # end sub delete

sub id_string {
	my $self = shift;
	if ( @_ ) {
		$$self{id_string} = $_[0];
	} # end if
	if ( ! $$self{id_string} ) {
		my $string = join(' ', ( $self->manufacturer(), $self->brand(), $self->finish(), $self->colour(), $self->weight() ) );
		if ( $$self{type} eq 'Roll' ) {
			$string .= ' ' . $$self{width}.'"' if $$self{width};
			$string .= ' Roll ';
		} else {
			if ( $$self{start_width} and ( ( $$self{width} != $$self{start_width} ) or ( $$self{height} != $$self{start_height} ) ) ) {
				$string .= ' ' . $$self{start_width}.'x'.$$self{start_height} . ' => '. $$self{width}.'x'.$$self{height} . ' ';
			} else {
				$string .= ' ' . $$self{width}.'x'.$$self{height} . ' ';
			} # end if
			#$string .= $self->mweight().'M ' if $self->mweight();
		} # end if
		$string .= sprintf('%.1fPT ', 1000*$$self{calliper}) if $self->calliper();
		$string .= $$self{gsm}.'gsm ' if $self->gsm();
		$string .= 'FSC:' . $$self{fsc_code} if $$self{fsc_code};
		$string .= 'Minimum: ' . $$self{minimum_order} if $$self{minimum_order};
		$$self{id_string} = $string;
	} # end if
	return $$self{id_string};
} # end sub id_string

sub to_string {
	my $self = shift;
	if ( @_ ) {
		$$self{to_string} = $_[0];
	} # end if
	if ( ! $$self{to_string} ) {
		my $string = join(' ', (
					($$self{supplied} ? 'Customer Supplied' : () ),
					($$self{id} ? () : 'Custom'),
					($self->manufacturer() ? $self->manufacturer() : () ),
          $self->brand(), $self->finish(), $self->colour(), $self->weight(),
					) );
		if ( $self->type() eq 'Roll' ) {
			$string .= ' ' . 1*$self->width.'"' if $$self{width};
			$string .= ' Roll ';
		} elsif ($self->type() eq 'Sheet' or ($self->type() eq 'Envelope')) {
			if ( $$self{start_width} and ( ( $$self{width} != $$self{start_width} ) or ( $$self{height} != $$self{start_height} ) ) ) {
				$string .= ' ' . $$self{start_width}.'x'.$$self{start_height} . ' => '. $$self{width}.'x'.$$self{height};
			} elsif ($$self{width} and $$self{height}) {
				$string .= ' ' . 1*$$self{width}.'x'.1*$$self{height};
			} # end if
			#$string .= $self->mweight().'M ' if $self->mweight();
		} # end if
		if (!$openprint::config{Show_Stock_Calliper} or $openprint::config{Show_Stock_Calliper} ne 'N' ) {
		$string .= ' '. Math::Round::nearest( 0.1, 1000*$self->calliper()).'PT' if $self->calliper() and ! ( $self->weight() =~ /PT/ );
		}
		if (!$openprint::config{Show_Stock_GSM} or $openprint::config{Show_Stock_GSM} ne 'N' ) {
		$string .= ' '. Math::Round::nearest(1, $self->gsm()).'gsm' if $self->gsm();
		}
		$string .= ' FSC:' . $$self{fsc_code} if $$self{fsc_code};
		#$string .= 'Minimum: ' . $$self{minimum_order} if $$self{minimum_order};
		$$self{to_string} = $string;
	} # end if
	return $$self{to_string};
} # end sub to_string

sub material {
	my ( $self, $material ) = @_;

	if ( defined $material ) {
		$material = openprint::StockMaterial->transform(name => $material);
		my $Material = openprint::StockMaterial->find_one('name lc'=> lc $material );
		if ( $Material ) {
			@$self{'material_id','material'} = @$Material{'id','name'};
		} else {
			@$self{'material_id','material'} = ( undef, $material );
		} # end if
	} elsif ( $$self{material_id} and ! $$self{material} ) {
		$$self{material} = new openprint::StockMaterial( $$self{material_id} )->name();
	} # end if
	return $$self{material};
} # end sub material

sub Material {
	return new openprint::StockMaterial( $_[0]{material_id} );
} # end sub Material

sub group {
	my ( $self, $group ) = @_;

	if ( defined $group ) {
		$group = openprint::StockGroup->transform('name',$group);
		my $Group = openprint::StockGroup->find_one('name lc'=> lc $group );
		if ( $Group ) {
			@$self{'group_id','group'} = @$Group{'id','name'};
		} else {
			@$self{'group_id','group'} = ( undef, $group );
		} # end if
	} elsif ( $$self{group_id} and ! $$self{group} ) {
		$$self{group} = new openprint::StockGroup( $$self{group_id} )->name();
	} # end if
	return $$self{group};
} # end sub group

sub Brand {
	if ( ! $_[0]{Brand} ) {
		$_[0]{Brand} = new openprint::StockBrand( $_[0]{brand_id} );
	} 
	return $_[0]{Brand};
}

sub brand {
  my $self = shift;
  if (@_) {
    $$self{brand} = openprint::StockBrand->transform(name=>shift);
    my $Brand = openprint::StockBrand->find_one('name lc'=> lc $$self{brand} ) if $$self{brand};
    if ( $Brand ) {
      @$self{'brand_id','brand'} = @$Brand{'id','name'};
      $$self{Brand} = $Brand;
    } else {
      $$self{brand_id} = undef;
    } # end if
	}

  if ($$self{brand_id} and !$$self{brand}) {
		$$self{Brand} = new openprint::StockBrand($$self{brand_id});
		$$self{brand} = $$self{Brand}->name();
	} # end if
	return $$self{brand} || '';
} # end sub brand

sub Manufacturer {
	return openprint::Manufacturer( $_[0]{manufacturer_id} );
}
sub manufacturer {
  my $self = shift;
	if ( @_ ) {
		my $new = openprint::Manufacturer->transform( 'name', shift );
		if ( ! $$self{custom} ) {
			my $Manufacturer = openprint::Manufacturer->find_one('name lc'=> lc $new );
			if ( $Manufacturer ) {
				@$self{'manufacturer_id','manufacturer'} = @$Manufacturer{'id','name'};
			} else {
				@$self{'manufacturer_id','manufacturer'} = ( undef, $new );
			} # end if
		} else {
			$$self{manufacturer} = $new;
			$$self{manufacturer_id} = undef;
		} # end if
	} elsif ( $$self{manufacturer_id} and ! $$self{manufacturer} ) {
		$$self{manufacturer} = new openprint::Manufacturer( $$self{manufacturer_id} )->name();
	} # end if
	return $$self{manufacturer};
} # end sub manufacturer

sub Finish {
	return new openprint::StockFinish( $_[0]{finish_id} );
}

sub finish {
  my $self = shift;
  if ( @_ ) {
    $$self{finish} = openprint::StockFinish->transform(name => shift);
    my $Finish = openprint::StockFinish->find_one('name lc'=> lc $$self{finish} ) if $$self{finish};
    if ( $Finish ) {
      @$self{'finish_id','finish'} = @$Finish{'id','name'};
    } else {
      $$self{finish_id} = undef;
    } # end if
  }

	if ($$self{finish_id} and !$$self{finish}) {
		$$self{finish} = new openprint::StockFinish( $$self{finish_id} )->name();
	} # end if
	return $$self{finish} || '';
} # end sub finish

sub Colour {
	return new openprint::StockColour( $_[0]{colour_id} );
}

sub colour {
  my $self = shift;

	if (@_) {
		$$self{colour} = openprint::StockColour->transform(name=> shift);
    $openprint::log->debug("Setting colour to ".$$self{colour});

    my $Colour = openprint::StockColour->find_one('name lc'=> lc $$self{colour} ) if $$self{colour};
    if ($Colour) {
      @$self{'colour_id','colour'} = @$Colour{'id','name'};
    } else {
      $$self{colour_id} = undef;
    } # end if
  }

  if ($$self{colour_id} and !$$self{colour}) {
    $$self{colour} = new openprint::StockColour( $$self{colour_id} )->name();
  } # end if

  return $$self{colour} // '';
} # end sub colour

sub Quality {
	return new openprint::StockQuality( $_[0]{quality_id} );
} # end sub Quality

sub quality {
	my ( $self, $quality ) = @_;
	if ( @_ > 1 ) {
		$quality = openprint::StockQuality->transform( 'name', $quality );
		if ( ! $$self{custom} ) {
			my $Quality = openprint::StockQuality->find_one('name lc'=>lc $quality );
			if ( $Quality ) {
				@$self{'quality_id','quality'} = @$Quality{'id','name'};
			} else {
				@$self{'quality_id','quality'} = ( undef, $quality );
			} # end if
		} else {
			$$self{quality} = $quality;
		} # end if
	} elsif ( $$self{quality_id} and ! $$self{quality} ) {
		$$self{quality} = new openprint::StockQuality( $$self{quality_id} )->name();
	} # end if
	return $$self{quality} || '';
} # end sub quality

sub Weight {
	return new openprint::StockWeight( $_[0]{weight_id} );
}

sub weight {
	my $self = shift;
	if ( @_ ) {
		$$self{weight} = openprint::StockWeight->transform(name=>shift);
    my $Weight = openprint::StockWeight->find_one('name lc'=>lc $$self{weight});
    if ( $Weight ) {
      @$self{'weight_id','weight'} = @$Weight{'id','name'};
    } else {
      $$self{weight_id} = undef;
    } # end if
	}
  if ($$self{weight_id} and ! $$self{weight}) {
		$$self{weight} = new openprint::StockWeight($$self{weight_id})->name();
	} # end if
  $$self{weight} //= '';
	return $$self{weight};
} # end sub weight

sub width {
	my ( $self, $width ) = @_;
	if ( defined $width ) {
		$width =~ s/[^\d\.]//g;
		$$self{width} = $width;
		delete $$self{to_string};
		delete $$self{id_string};
	} # end if
	return $$self{width};
} # end if

sub height {
	my ( $self, $height ) = @_;
	if ( defined $height ) {
		$height =~ s/[^\d\.]//g;
		$$self{height} = $height;
		delete $$self{to_string};
		delete $$self{id_string};
	} # end if
	return $$self{height};
} # end if

# It is nearly impossible to accurately figure out the mweight of an envelope, we can do *2, but that's not accurate.
sub mweight {
	my $self = shift;
	if ( @_ ) {
		$$self{mweight} = $self->transform(mweight=>shift);
		$self->wpsi(undef) if $$self{mweight};
	} # end if
	if ( ! $$self{mweight} ) {
		if ( $$self{gsm} and $$self{gsm} ne 'unknown') {
			my $wpsi = $$self{gsm}/703064.5;
			if ( $$self{type} eq 'Roll' and $$self{basis_width} and $$self{basis_height} ) {
				$$self{mweight} = Math::Round::round( $wpsi * $$self{basis_width} * $$self{basis_height} * 1000 );
$openprint::log->debug("Setting mweight to $$self{mweight} from wpsi $wpsi and basis size");
				# MWeight is in relation to the basis size
			} elsif ( $$self{width} and $$self{height} ) {
        if ($self->is_envelope()) {
          $$self{mweight} = Math::Round::round( $wpsi * $$self{width} * $$self{height} * 500 );
        } else {
          $$self{mweight} = Math::Round::round( $wpsi * $$self{width} * $$self{height} * 1000 );
        } # endif

			} # end if
		} elsif ($self->basis_mweight()) {
			$$self{mweight} = Math::Round::round(($$self{basis_mweight}*$$self{width}*$$self{height})/($self->basis_width()*$self->basis_height()));
      $openprint::log->debug("Auto calcing mweight from basis" . $self->weight() );
		} elsif ( ! $self->weight() =~ /\D/ ) {
			# weight of 500sheets of 25x38
      $openprint::log->debug("Auto calcing mweight from " . $self->weight());
			$$self{mweight} = Math::Round(($self->weight()*$$self{width}*$$self{height})/($self->basis_width()*$self->basis_height()));
		} # end if
		$self->wpsi(undef);
	} # end if
	return $$self{mweight};
} # end sub mweight

sub calliper {
  my $self = shift;
  $$self{calliper} = $self->transform(calliper=>shift) if @_;
  
  if (!$$self{calliper}) {
    if ($self->weight() and ($self->weight() =~ /(\d+)\s(PT)/i)) {
      $$self{calliper} = $1/1000;
    } elsif ($self->finish()) {
      if ($self->finish() =~ /offset/i) {
        if ( Math::Round::nearest(10,$self->basis_mweight()) == 70 ) {
          $$self{calliper} = 0.005;
        }
      } elsif ( $self->finish() =~ /gloss/i ) {
        if ( $self->finish() =~ /cover/i ) {
          $$self{calliper} = Math::Round::nearest(10,$self->basis_mweight()) / 10000;
        } else {
          $$self{calliper} = Math::Round::nearest(10,$self->basis_mweight()) / 20000;
        }
      } elsif ( $self->finish() =~ /silk/i ) {
        $$self{calliper} = Math::Round::nearest(10,$self->basis_mweight()) / 20000;
      }
    } # end if finish
	}
	return $$self{calliper};
} # end sub calliper

sub sheetsize {
	my $self = shift;

	if ( $$self{type} eq 'Roll' ) {
		if ( $$self{width} ) {
			return $$self{width} . '"';
		} # end if
		return '';
	} else {
		return sprintf('%s" x %s"', @$self{'width','height'} );
	} # end if
} # end sub sheetsize

sub size {
	my $self = shift;

	if ( $$self{type} eq 'Roll' ) {
		if ( $$self{width} ) {
			return (1*$$self{width}) . '"';
		} # end if
		return '';
	} else {
		return sprintf('%s" x %s"', 1*$$self{width}, 1*$$self{height} );
	} # end if
} # end sub size

sub size_id {
	return $_[0]->size();
}

sub Owner {
	my ( $self, $Owner ) = @_;
	if ( defined $Owner ) {
		$$self{owner_id} = $Owner->id();
	} # end if
	return new openprint::Company( $$self{owner_id} );
} # end sub Owner

sub owner {
	my $self = shift;
	my $Company;
	if ( @_ and $_[0] ) {
		my @Companies = openprint::Company->find(name=>$_[0]);
		if ( ! @Companies ) {
			$Company = new openprint::Company();
			$Company->name( $_[0] );
			$Company->save();
		} else {
			$Company = $Companies[0];
		} # end if

		$$self{owner_id} = $Company->id();
	} else {
		$Company = new openprint::Company( $$self{owner_id} );
	} # end if
	return $Company->name();
} # end sub owner

sub owner_id {
	my $self = shift;
	if ( @_ ) {
		$$self{owner_id} = shift;
		#$$self{owner_id} =~ s/\D//g;
	} # end if
	return $$self{owner_id};
} # end sub owner_id

# This function assumes that the skid contents have already been updated
sub add_inventory {
	my ( $self, $Skid, $quantity, $units, $description, $Project ) = @_;
	$quantity =~ s/[^\-\d]//g;
	$quantity = int $quantity;

	if ( ! $Project ) {
		my $docket;
		if ( $description =~ /docket (\d+)/ ) {
			$docket = $1;
		} # end if
		if ( $docket ) {
			my @Projects = openprint::Project->find(docket=>$docket);
			$Project = $Projects[0] if @Projects;
		} else {
			$Project = new openprint::Project();
		} # end if
	} # end if

	$units = $self->units() if ! $units;
	my $PI = new openprint::PaperInventory();
	$PI->save({
		paper_id	=>	$$self{id},
		user_id		=>	$openprint::session{user_id},
		poindex		=>	undef,
		instock		=>	$self->in_stock() + $quantity,
		delta		=>	$quantity,
		comment		=>	$description,
		skid_id		=>	$Skid->id(),
		units		=>	$units,
		docket		=>	$$Project{docket},
		project_id	=>	$$Project{id},
		});
	# Updates in_stock and allocated
	delete $$self{SkidContents};
	$self->save();
} # end sub add_inventory

sub allocate {
	my ( $self, $skid_id, $docket, $quantity, $units, $condition_id ) = @_;

	my $Order;
	if ( ref $docket eq 'openprint::Order' ) {
		$Order = $docket;
		$docket = $$Order{docket};
	} elsif ( $docket ) {
		$Order = openprint::Order->find_one( docket => $docket );
	} # end i

	my $skids;
	if ( ref $skid_id eq 'openprint::Skid' ) {
		$skids = [ $skid_id->id() ];
	} elsif ( ref $skid_id eq '' ) {
		$skids = [ $skid_id ];
	} else {
		$skids = $skid_id;
	} # end if

	$quantity = POSIX::ceil( $quantity );

  require openprint::PaperAllocation;
	my $PA = new openprint::PaperAllocation();
	$PA->save( {
			paper_id		=>	$$self{id},
			skid_ids		=>	$skids,
			quantity		=>	$quantity,
			units			=>	$units ? $units : $self->units(),
			docket			=>	$docket,
			operator_id		=>	$openprint::session{user_id},
			condition_id	=>	$condition_id,
			} );
	if ( $Order ) {
		$Order->add_log( qq`Allocated $quantity$$PA{units} of <a href="/employee/inventory/paper_details.html?paper_id=$$self{id}">` . $self->to_string().'</a>');
			my $PI = new openprint::PaperInventory();
			$PI->save({	
				paper_id	=>	$$self{id},
				user_id		=>	$openprint::session{user_id},
				docket		=>	$Order->docket(),
				delta		=>	0,
				comment		=>	qq`Allocated $quantity$$PA{units} to docket $$Order{docket}`,
				instock		=>	$self->in_stock(),
			});
	} else {
			my $PI = new openprint::PaperInventory();
			$PI->save({	
				paper_id	=>	$$self{id},
				user_id		=>	$openprint::session{user_id},
				delta		=>	0,
				comment		=>	qq`Allocated $quantity$$PA{units}`,
				instock		=>	$self->in_stock(),
			});
	} # end if
	if ( $$self{available_to_order} > 1 ) {
		$$self{available_to_order} -= $quantity;
	} # end if		
	$_ = $self->save();
	delete $$self{available};
	return $PA;
} # end sub allocate

sub back_ordered {
	my $self = shift;
	return 0 if ! $$self{id};

	return 0;
} # end sub back_ordered

sub allocated {
	return 0 if ! $_[0]{id};
  require openprint::PaperAllocation;
	my ( $self, $docket, $new ) = @_;
	if ( @_ == 3 ) {
		$$self{allocated} = $new;
	} # end if
	if ( $docket ) {
		my $qty = misc::sum( map { $_->quantity() } openprint::PaperAllocation->find(paper_id=>$$self{id}, docket=>$docket) );
		return $qty;
	} # end if
	if ( ! defined $$self{allocated} ) {
		$$self{allocated} = misc::sum( map { $_->quantity() } openprint::PaperAllocation->find(paper_id=>$$self{id}) ) // 0;
	} # end if
	return $$self{allocated};
} # end sub allocated

sub in_stock {
	return 0 if ! $_[0]{id};

	if ( @_ > 1 ) {
		#$openprint::log->debug("Setting paper in_stock to " . ( $_[1] ? $_[1] : 'undef' ));
		if ( ref $_[1] eq 'openprint::InventoryCondition' ) {
			my $in_stock = 0;
			foreach my $C ( openprint::SkidContent->find(deleted=>0,paper_id=>$_[0]{id}, condition_id=>$_[1]->id() ) ) {
				$in_stock += $C->quantity();
			} # end foreach C
			return $in_stock;
		} else {
			$_[0]{in_stock} = $_[1];
			delete $_[0]{SkidContents};
		} # end if
	} # end if

	if ( ! defined $_[0]{in_stock} ) {
		$_[0]{in_stock} = 0;
		foreach my $SkidContent ( $_[0]->SkidContents() ) {
			$_[0]{in_stock} += $SkidContent->quantity();
		} # end foreach SkidContent
		#$openprint::log->debug("Loading paper in_stock to $_[0]{in_stock}");
	} # end if
	return $_[0]{in_stock};
} # end sub in_stock

sub SkidContents {
	if ( @_ > 1 ) {
		$_[0]{SkidContents} = $_[1];
	} # end if
	if ( ! $_[0]{SkidContents} ) {
		$_[0]{SkidContents} = [ openprint::SkidContent->find(deleted=>0,paper_id=>$_[0]{id},'quantity >'=>0,'location null or not in'=>['Missing']) ];
	} # end if
	return @{$_[0]{SkidContents}};
} # end sub SkidContents

sub available {
	my $self = shift;
	if ( @_ ) {
		if ( defined $_[0] ) {
			$$self{available} = $_[0];
		} else {
			delete $$self{available};
		} # end if
	} # end if
	return 0 if ! $$self{id};

	if ( ! exists $$self{available} ) {
		$$self{available} = 0;
		foreach my $SkidContent ( $self->SkidContents() ) {
			next if sets::isin( $SkidContent->condition(), ['Damaged', 'Used' ] );
			@$self{available} += int $SkidContent->quantity();
		} # end foreach SkidContent
		$$self{available} -= $self->allocated();
	} # end if
	return $$self{available};
} # end sub available

sub skids {
	return 0 if ! $_[0]{id};
	if ( $_[0]{SkidContents} ) {
		return map { $_->Skid() } @{$_[0]{SkidContents}};
	} else {
		return openprint::Skid->find( 'paper_id any'=>$_[0]{id}, 'quantity >='=>1);
	} # end if
	#return map { new openprint::Skid( $_ ) } sql::execute( undef, undef, q{SELECT skid_id FROM skid_contents WHERE paper_id=? and quantity > 0}, $$self{id} );
} # end sub skids

sub previous {
	my $self = shift;
	my @papers = openprint::Paper->find( 
columns   =>  '*,(select name from stockbrands where id=brand_id) AS brand, (select name from stockfinishes where id=finish_id) AS finish, (select name from stockcolours where id=colour_id) AS colour, (select name from stockweights where id=weight_id) AS weight',
order=>'brand,finish,colour,weight,'.$fields{width}.','.$fields{height} );
	for ( my $i = 0; $i < @papers; $i += 1 ) {
		return $papers[$i-1] if ($papers[$i] == $self )and ($i > 0);
	} # end if
	return $self;
} # end sub previous

sub next {
	my $self = shift;
	
	my @papers = openprint::Paper->find( 
			columns   =>  '*,(select name from stockbrands where id=brand_id) AS brand, (select name from stockfinishes where id=finish_id) AS finish, (select name from stockcolours where id=colour_id) AS colour, (select name from stockweights where id=weight_id) AS weight',
			brand_id=>$$self{brand_id},
order=>'brand,finish,colour,weight,'.$fields{width}.','.$fields{height} );
	for ( my $i = 0; $i < @papers-1; $i += 1 ) {
		return $papers[$i+1] if ( $papers[$i]{id} == $$self{id} ) and ($i < @papers-1);
	} # end if
	@papers = openprint::Paper->find( 
			columns   =>  '*,(select name from stockbrands where id=brand_id) AS brand, (select name from stockfinishes where id=finish_id) AS finish, (select name from stockcolours where id=colour_id) AS colour, (select name from stockweights where id=weight_id) AS weight',
order=>'brand,finish,colour,weight,'.$fields{width}.','.$fields{height} );
	for ( my $i = 0; $i < @papers-1; $i += 1 ) {
		return $papers[$i+1] if ( $papers[$i]{id} == $$self{id} ) and ($i < @papers-1);
	} # end if

	return $self;
} # end sub next

sub Recommendations {
	my $self = shift;
	if ( @_ ) {
		@{$$self{Recommendations}} = @_;
	} elsif ( ! exists $$self{Recommendations} ) {
		if ( $$self{id} ) {
			$$self{Recommendations} = [ openprint::PaperRecommendation->find(paper_id=>$$self{id}) ];
      $openprint::log->debug('No Recommendations') if !@{$$self{Recommendations}};
		} else {
      $openprint::log->debug('No id in recommendations');
			$$self{Recommendations} = [];
		} # end if
	} # end if
	return @{$$self{Recommendations}};
} # end sub Recommendations

sub recommendations {
	my $self = shift;
	if ( @_ ) {
		@{$$self{recommendations}} = @_;
	} elsif ( ! exists $$self{recommendations} ) {
    $openprint::log->debug("No recommendations");
		if ( $$self{id} ) {
			$$self{recommendations} = [ sql::execute( $openprint::log, $openprint::dbh, q{SELECT lngProjectTypeIndex FROM tbl_paper_recommendations WHERE lngPaperIndex=?}, $$self{id} ) ];
		} else {
      $openprint::log->debug("No id in recommendations");
			$$self{recommendations} = [];
		} # end if
	} # end if
	return @{$$self{recommendations}};
} # end sub recommendations

# From now on, qty is always weight
sub get_price {
	my ( $self, %params ) = @_;
	
	my $price;
	my $qty = $params{weight} ? $params{weight} : $params{sheets};
	my $lookup_qty = $params{lookup_weight} ? $params{lookup_weight} : $qty;
	if ( (!$lookup_qty) and ($params{service} eq 'Material') ) {
		Carp::cluck("Paper qty lookup with no qty");
		$openprint::log->error("Paper qty lookup with no qty");
	} #end if

	if ( $$self{Price} and ($params{service} eq 'Material') ) {
		# If custom paper
		$price = { price => $$self{Price}, cost=>$$self{Price}, units=>$$self{Units} };
#$openprint::log->debug("Usnig custom price $$self{Price}$$self{Units}");
	} elsif ( $$self{id} ) {
		my @Prices = $self->Prices( );
		if ( (! $$self{supplied} ) and ! @Prices ) {
			$openprint::log->warn( "No prices for paper for paper " . $self->to_string() );
			return;
		} # end if
		my $list_id = openprint::pricing::get_pricelist_id( );
		foreach my $Price ( @Prices ) {
			next if $$Price{pricelist_id} != $list_id;
			next if ( $params{equipment_id} and $$Price{equipment_id} and ( $params{equipment_id} != $$Price{equipment_id} ) );
			next if $$Price{service} ne $params{service};
#$openprint::log->warn(sprintf('Price: %s - %s : %s',$Price->min(), $Price->max(), $Price->price() ) );
			if ( 
					( (!$Price->min()) or $Price->min() <= $lookup_qty ) and
					( (!$Price->max()) or $Price->max() >= $lookup_qty )
				) {
				$price = $Price->clone();
				last;
			} # end if
		} # end foreach Price
		if ( ! $price ) {
			if ( ( ! $$self{supplied} ) and ( $params{service} eq 'Material' or $debug ) ) {
				$openprint::log->warn("Unable to find price for Stock id:$$self{id} $params{service} equip: $params{equipment_id} : $qty $lookup_qty");
				foreach my $Price ( @Prices ) {
					if ( $$Price{pricelist_id} != $list_id ) {
						$openprint::log->debug("Wrong pricelist: " . $Price->to_string() );
						next;
					} 
					if ( $params{equipment_id} and $$Price{equipment_id} and ( $params{equipment_id} != $$Price{equipment_id} ) ) {
						$openprint::log->debug("Wrong equipment: " . $Price->to_string() );
						next;
					}
					if ( $$Price{service} ne $params{service} ) {
						$openprint::log->debug("Wrong service: " . $Price->to_string() );
						next;
					} 
#$openprint::log->warn(sprintf('Price: %s - %s : %s',$Price->min(), $Price->max(), $Price->price() ) );
					if ( 
							( (!(1*$Price->min())) or $Price->min() <= $lookup_qty ) and
							( (!(1*$Price->max())) or $Price->max() >= $lookup_qty )
					   ) {
						$price = $Price->clone();
						last;
					} else {
						$openprint::log->debug("Wrong qty: $lookup_qty" . $Price->to_string() );
					} # end if
				} # end foreach Price
				
			} # end if
			return;
		} # end if ! price


		my $Pricelist = new openprint::Pricelist( $list_id );
		$$price{currency_id} = $Pricelist->currency_id();
		openprint::Currency::convert( $price );
	} else {
		Carp::cluck("No custom price, and no paper::id for service: $params{service}" . $self->to_string()) if $debug;
	} # end if

	if ( 0 and $price and $openprint::config{ApplyMarkup} ) {
	#if ( (!$$self{custom}) and $openprint::config{ApplyMarkup} ) {
		my $new_price = $$price{price} * ( 1 + ( $openprint::config{ApplyMarkup} / 100 ) );
		$openprint::log->debug("Apply Markup: $$price{price} * ( 1 + $openprint::config{ApplyMarkup} / 100 ) = $new_price " ) if DEBUG_PRICING;
		$$price{price} = $new_price;
	} # end if

	my $CSR = $openprint::Company->CSR();

	if ( $$openprint::Company{discount} or $$openprint::Company{csr_commission} or $$openprint::Company{credit_card_fee} or $$CSR{commission} ) {
		my $discount = 1 - ($$openprint::Company{discount} / 100);
		my $csr_commission = 1 + (! defined($openprint::Company->csr_commission()) ? $$CSR{commission} : $$openprint::Company{csr_commission} ) /100;
		my $credit_card_fee = 1 + ($$openprint::Company{credit_card_fee}/100);

		$_ = $$price{price};
		$$price{price} *= $discount;
		$openprint::log->debug("Apply discount: $_ * ( 1 + $discount / 100 ) = $$price{price} " ) if DEBUG_PRICING;
		$_ = $$price{price};
		$$price{price} *= $csr_commission;
		$openprint::log->debug("Apply commission: $_ * ( 1 + $csr_commission / 100 ) = $$price{price} " ) if DEBUG_PRICING;
		$_ = $$price{price};
		$$price{price} *= $credit_card_fee;
		$openprint::log->debug("Apply credit_card fee: $_ * ( 1 + $credit_card_fee / 100 ) = $$price{price} " ) if DEBUG_PRICING;
	} # end if

	if ( $params{service} eq 'Material' ) {
	# Don't need to cut it because the mweight has already byeen cut
		#$$price{mweight} = $self->mweight();
		# Prices are always stored in cwt now
		#if ( ! $$self{mweight} ) {
			# ROll papers won't have an mweight
			$$price{'100lb'} = $$price{price};
			$$price{'100lb Cost'} = $$price{cost};
			$$price{'100lb Price'} = $$price{price};
			#$price{Cost} *= $$self{wpsi} * $$self{width} * $$self{height};
			#$price{Price} *= $$self{wpsi} * $$self{width} * $$self{height};
		#} else {
			#$$price{'100lb'} = $$price{price};
			#$$price{'100lb Cost'} = $$price{cost};
			#$$price{'100lb Price'} = $$price{price};
			#$price{Cost} *= $$self{mweight} / 100000;
			#$price{Price} *= $$self{mweight} / 100000;
		#} # end if
		$$price{'100lb Total'} = $$price{'100lb Price'} * $qty/100;
	} # end if
$openprint::log->debug("Costs: cost($$price{cost}) Price($$price{'100lb Price'})/100lb cost($$price{'100lb Cost'})/cwt Price($$price{Price}) qty($qty) lookup_qty($lookup_qty) Total($$price{'100lb Total'})") if DEBUG_PRICING;
	return $price;
} # end sub get_price


sub cut {
	my $self = shift;
	if ( @_ ) {
		my ( $new_width, $new_height ) = @_;
		$$self{mweight} = int( $$self{mweight} / ( ( $$self{width} * $$self{height} ) / ( $new_width * $new_height ) ) );
		$$self{width} = $new_width;
		$$self{height} = $new_height;
	} else {
		if ( $$self{height} > $$self{width} ) {
			$$self{height} /= 2;
		} else {
			$$self{width} /= 2;
		} # end if
		$$self{mweight} /= 2;
	} # end if
	delete $$self{to_string};
	delete $$self{id_string};
	$$self{grain_direction} = undef; # force recalc of gd
} # end sub cut

sub minimum_order {
	if ( @_ > 1 ) {
		$_[0]{minimum_order} = $_[1];
	} # end if

#$openprint::log->debug("SPP: $$self{start_width} / $$self{width} ) * int( $$self{start_height} / $$self{height} * spp $$self{sheets_per_package} * $factor;");
	return 0 if ! $_[0]{minimum_order};
	return $_[0]{minimum_order} * $_[0]->factor();
} # end minimum_order 

sub minimum_order_weight {
	my $self = $_[0];
	if ( ! exists $$self{minimum_order_weight} ) {
		if ( $$self{type} eq 'Sheet' ) {
			$$self{minimum_order_weight} = Math::Round::nearest( 0.1, $self->minimum_order() * $self->sheet_weight() );
		} else {
			$$self{minimum_order_weight} = $self->minimum_order();
		} # end if
	} # end if
	return $$self{minimum_order_weight};
} # end sub minimum_order_weight

# Factor is an integer because it is the # of useable sheets we can get out of the supplied sheet.
sub factor {
	my $factor = int($_[0]{start_width} / $_[0]{width} ) * int( $_[0]{start_height} / $_[0]{height} ) if $_[0]{width} and $_[0]{height};
	#my $factor = Math::Round::nearest(0.1,$_[0]{start_width} / $_[0]{width} ) * Math::Round::nearest(0.1, $_[0]{start_height} / $_[0]{height} ) if $_[0]{width} and $_[0]{height};
	return 1 if ! $factor;
	return $factor;
} # end sub factor

sub sheets_per_package {
	my $self = shift;
	if ( @_ ) {
		$$self{sheets_per_package} = shift;
	} # end if

  $$self{sheets_per_package} //= 0;
#$openprint::log->debug("SPP: $$self{start_width} / $$self{width} ) * int( $$self{start_height} / $$self{height} * spp $$self{sheets_per_package} * $factor;");
	return $$self{sheets_per_package} * $self->factor();
} # end sheets_per_package
	
# GSM is gsm for the item, so of an envelope, not the source sheet
sub gsm {
	my $self = shift;
	if (@_) {
		$$self{gsm} = shift;
		if ($$self{gsm}) {
			$self->wpsi(undef);
			$self->mweight(undef);
			$self->basis_mweight(undef);
		}
	} 
	if (!$$self{gsm}) {
    if ($$self{mweight} and $self->type() ne 'Roll') {
      my $wpsi = $$self{mweight} / ($$self{width}*$$self{height}*1000);
			$$self{gsm} = Math::Round::nearest( 0.01, $wpsi * 703064.5 );
			$openprint::log->debug('calculate gsm for ' . $$self{id} . ' ' . $self->to_string() ) if $$self{brand};
    } elsif ($self->wpsi(undef)) {
			$$self{gsm} = Math::Round::nearest( 0.01, $$self{wpsi} * 703064.5 );
			$openprint::log->debug('calculate gsm for ' . $$self{id} . ' ' . $self->to_string() ) if $$self{brand};
		} elsif ($$self{id}) { 
			$$self{gsm} = 'unknown';
			$openprint::log->warn('Cant calculate gsm for ' . $$self{id} . ' ' . $self->to_string() ) if $$self{brand};
		} # end if
	} # end if
	return $$self{gsm};
} # end sub gsm

# Is wpsi of the finished thing, or the source sheet?  I think the item. Same as mweight
sub wpsi {
	my $self = shift;

	if ( @_ ) {
#$log->debug("Setting wpsi was $$self{wpsi}") if 1;
		$$self{wpsi} = $self->transform(wpsi=>shift);
#$log->debug("Setting wpsi to $$self{wpsi}") if 1;
	} # end if

	if (!$$self{wpsi}) {
    if ($$self{mweight} and $$self{width} and $$self{height}) {
      $$self{wpsi} = ($$self{mweight} / 1000)/($$self{width}*$$self{height});
      #$$self{wpsi} *= 2 if $self->is_envelope();
      $log->debug("Setting wpsi to mweight ($$self{mweight} / 1000)/($$self{width}*$$self{height}) = $$self{wpsi}");
    } elsif ($self->basis_mweight()) {
			$$self{wpsi} = ($$self{basis_mweight}/1000)/($self->basis_width()*$self->basis_height());
      if ($self->is_envelope()) {
        $$self{wpsi} *= 2;
        $log->debug("Setting wpsi to $$self{wpsi} from envelope 2 * basisweight ($$self{basis_mweight}/1000)/($$self{basis_width}*$$self{basis_height}");
      } else {
        $log->debug("Setting wpsi to $$self{wpsi} from basisweight ($$self{basis_mweight}/1000)/($$self{basis_width}*$$self{basis_height}");
      }
    } elsif ( $$self{gsm} and $$self{gsm} ne 'unknown') {
			$$self{wpsi} = $$self{gsm} / 703064.5;
$log->debug("Setting wpsi from gsm to $$self{gsm} / 703064.5 = $$self{wpsi}");
		#} else {
#$log->debug("Nothing to set wpsi from");
		} # end if
	} # end if
	return $$self{wpsi};
} # end if wpsi

sub JDF_Media {
	my ( $self, $doc ) = @_;

	my $Paper = $doc->createElement('Media');
	$Paper->setAttribute('Status','Available');
	$Paper->setAttribute('MediaType','Paper');
	$Paper->setAttribute('MediaUnit', $self->type() );
	$Paper->setAttribute('Brand',$self->brand() );
	#$Paper->setAttribute('Class', 'Consumable' );
	#$Paper->setAttribute('Grade', '1' );
	#$Paper->setAttribute('Locked', 'false' );
	$Paper->setAttribute('DescriptiveName',$self->to_string() );
	$Paper->setAttribute('ProductID',$self->id() );
	#$Paper->setAttribute('ID', 'Paper' );
	if ( $$self{width} > $$self{height} ) {
	$Paper->setAttribute( 'Dimension',join(' ', $$self{width} *72, $$self{height}*72) );
	$Paper->setAttribute('GrainDirection', 'ShortEdge' );
	} else {
	$Paper->setAttribute( 'Dimension',join(' ', $$self{height} *72, $$self{width}*72) );
	$Paper->setAttribute('GrainDirection', 'LongEdge' );
	} # end if
	$Paper->setAttribute('Thickness', int($$self{calliper}*25400));
	$Paper->setAttribute('Weight', .99*int $self->gsm() );

	return $Paper;	
} # end sub jdf

sub JDF_MediaIntent {
	my ( $self, $doc, $sig_index ) = @_;

	my $Paper = $doc->createElement('MediaIntent');
	$Paper->setAttribute('Status','Available');
	#$Paper->setAttribute('MediaUnit', $self->type() eq 'Roll' ? '' : 'Sheet' );
	#$Paper->setAttribute('Brand',$self->brand() );
	$Paper->setAttribute('Class', 'Intent' );
	$Paper->setAttribute('Locked', 'false' );
	$Paper->setAttribute('DescriptiveName',$self->to_string() );
	$Paper->setAttribute('ProductID',$self->id() );
	#$Paper->setAttribute('Type', 'ConventionalPrinting' );
	$Paper->setAttribute('ID', 'Paper'.$sig_index );
	#$Paper->setAttribute( 'Dimensions',join(' ',
				#Math::Calc::Units::convert($$self{width}.'in','mm'),
				#Math::Calc::Units::convert($$self{height}.'in','mm'),
#) );

	my $MediaType = $Paper->appendChild( $doc->createElement( 'MediaType' ) );
	$MediaType->setAttribute('DataType','EnumerationSpan');
	$MediaType->setAttribute('Preferred','Paper');

	my $Grade = $Paper->appendChild( $doc->createElement( 'Grade' ) );
	$Grade->setAttribute('DataType','IntegerSpan');
	$Grade->setAttribute('Preferred','1');

	my $Weight = $Paper->appendChild( $doc->createElement( 'Weight' ) );
	$Weight->setAttribute('DataType','NumberSpan');
	$Weight->setAttribute('Preferred', $$self{mweight}*.45359237 ); #Kg

	my $Thickness = $Paper->appendChild( $doc->createElement( 'Thickness' ) );
	$Thickness->setAttribute('DataType','NumberSpan');
	$Thickness->setAttribute('Preferred', $$self{calliper}*25.4 ); #mm

	my $GrainDirection = $Paper->appendChild( $doc->createElement( 'GrainDirection' ) );
	$GrainDirection->setAttribute('DataType','EnumerationSpan');
	$GrainDirection->setAttribute('Preferred', 'LongEdge' );

	my $MediaColor = $Paper->appendChild( $doc->createElement( 'MediaColor' ) );
	$MediaColor->setAttribute('DataType','EnumerationSpan');
	$MediaColor->setAttribute('Preferred',$self->colour() );

	my $MediaBrand = $Paper->appendChild( $doc->createElement( 'StockBrand' ) );
	$MediaBrand->setAttribute('DataType','StringSpan');
	$MediaBrand->setAttribute('Preferred',$self->brand() );

	my $FrontCoatings = $Paper->appendChild( $doc->createElement( 'FrontCoatings' ) );
	$FrontCoatings->setAttribute('DataType','EnumerationSpan');
	$FrontCoatings->setAttribute('Preferred',$openprint::JDF::coatings{$self->finish()} );

	my $BackCoatings = $Paper->appendChild( $doc->createElement( 'BackCoatings' ) );
	$BackCoatings->setAttribute('DataType','EnumerationSpan');
	$BackCoatings->setAttribute('Preferred', $self->doublesided() ? $openprint::JDF::coatings{$self->finish()} : undef );
	
	return $Paper;	
} # end sub jdf

sub multipart {
	my $self = shift;

	if ( @_ ) {
		$$self{multipart} = int shift;
	} # end if
	return $$self{multipart};
}

sub load_from_signature {
	my ( $Project, $specs, $qty_index ) = @_;

	#$qty_index = $Project->ordered_quantity_index() if ! $qty_index;

	my $Paper;
  if ($Project and ($Project->type() eq 'NoPrint')) {
    $Paper = new openprint::Paper();
    $Paper->calliper($$specs{txtStockCalliper});
    $$Paper{width} = $$specs{flat_width};
    $$Paper{height} = $$specs{flat_height};

    return $Paper;
  }
	if ($$specs{rdbSpecificStock} and ($$specs{rdbSpecificStock} eq 'Y')) {
		$Paper = new openprint::Paper();
		$$Paper{custom} = 1;
		$Paper->brand( $$specs{txtSpecificStockBrand} );
		$Paper->finish( $$specs{txtSpecificStockFinish} );
		$Paper->colour( $$specs{txtSpecificStockColour} );
		$Paper->weight( $$specs{txtSpecificStockWeight} );
		$Paper->calliper( $$specs{txtSpecificStockCalliper} );
		$Paper->start_width( 1*$$specs{txtSpecificStockWidth} );
		$Paper->start_height( 1*$$specs{txtSpecificStockHeight} );
		$Paper->type( $$specs{StockType} );
		#if ( $qty_index ) {
			#$Paper->width( $$specs{'StockWidth'.$qty_index} );
			#$Paper->height( $$specs{'StockHeight'.$qty_index} ) if $Paper->type() ne 'Roll';
		#} else {
			$Paper->width( 1*$$specs{txtSpecificStockWidth} );
			$Paper->height( 1*$$specs{txtSpecificStockHeight} ) if $Paper->type() ne 'Roll';
		#} # end if
		$Paper->gsm( $$specs{txtStockGSM} ) if $$specs{txtStockGSM};

		$Paper->minimum_order( $$specs{minimum_order} );
		$Paper->sheets_per_package( $$specs{sheets_per_package} );
		$Paper->full_packages( $$specs{full_packages} );
		$Paper->cuttable( exists $$specs{cuttable} ? $$specs{cuttable} : 1 );
		$Paper->digital(1);
		if ( $$specs{perfecting} eq '' ) {
			$$Paper{perfecting} = ( $$specs{StockGrade} == 4 or $$specs{StockGrade} == 5 ) ? 'Y' : 'N';
		} elsif ( $$specs{perfecting} eq 'Y' ) { 
			$$Paper{perfecting} = 'Y';
		} elsif ( $$specs{perfecting} eq 'N' ) {
			$$Paper{perfecting} = 'N';
		} else {
			$$Paper{perfecting} = $$specs{perfecting};
		} # end if

		$Paper->doublesided($$specs{CustomSheetDoubleSided});
		$Paper->grade( $$specs{StockGrade});

		$$Paper{Price} = $$specs{CustomStockPrice};
		$$Paper{Units} = $$specs{CustomStockPriceUnits};
		# For Sheets, the basis weight fields aren't visible and don't get updated.
		$Paper->basis_width( $$specs{basis_width} );
		$Paper->basis_height( $$specs{basis_height} );
		$Paper->basis_mweight( $$specs{basis_mweight} ) if $$specs{basis_mweight};
		$Paper->score_required( $Paper->calliper() > 0.008 );
		#if ( $$specs{StockType} ne 'Roll' ) {
			$Paper->mweight( $$specs{txtCustomMWeight} ) if $$specs{txtCustomMWeight};
		#} # end if
		$Paper->supplied( $$specs{rdbSuppliedStock} eq 'Y' ? 1 : 0 );
		$$Paper{Supplied} = $Paper;
	} else {

		if ( $qty_index and $$specs{'paper_id'.$qty_index} ) {
      $openprint::log->debug("Loading by paper_id and qty_index");
			$Paper = openprint::Paper->find_one( id=>$$specs{'paper_id'.$qty_index} );
			if ( !$Paper ) {
				$openprint::log->warn('Loading by paper id but not found: ' . $$specs{'paper_id'.$qty_index} );
			} else {
				$$Paper{Supplied} = $Paper->clone();
			} # end if
		#} else {
			#Carp::cluck("load_from_signature called without qty_index:$qty_index and paper_id:". $$specs{'paper_id'.$qty_index});
		}
    if ( $$specs{hdnPaperIndex}) {
      $openprint::log->debug("Load by hdnPaper Index") if DEBUG;
			$Paper = openprint::Paper->find_one( id=>$$specs{hdnPaperIndex} );
			if ( !$Paper ) {
				$openprint::log->warn('Loading by paper id but not found: ' . $$specs{hdnPaperIndex} );
			} else {
        $Paper->width(1*$Paper->width());
        $Paper->height(1*$Paper->height());
        $Paper->start_width(1*$Paper->width());
        $Paper->start_height(1*$Paper->height());
				$$Paper{Supplied} = $Paper->clone();
        if ($$specs{hdnSheetSizeWidth}) {
          $Paper->width(1*$$specs{hdnSheetSizeWidth});
          $Paper->height(1*$$specs{hdnSheetSizeHeight});
        }
      } # end if
    } elsif($$specs{paper}) {
			$Paper = openprint::Paper->find_one( id=>$$specs{paper}{index} );
    }
    if ($Paper) {
      $openprint::log->debug("Returning paper ".$Paper->to_string()) if DEBUG;
      return $Paper;
    }

		if ( ! ( $$specs{ddmStockBrand} and $$specs{ddmStockFinish} and $$specs{ddmStockColour} and $$specs{ddmStockWeight} ) ) {
      $openprint::log->debug("No brand, colour etc, can't find stock");
			return new openprint::Paper();
		} # end if

    my %params = (
      'supplied is null or ='	=> $$specs{rdbSuppliedStock},
      brand	 	=> $$specs{ddmStockBrand},
      finish	=> $$specs{ddmStockFinish},
      colour	=> $$specs{ddmStockColour},
      weight	=> $$specs{ddmStockWeight},
      ( $Project ? ( 'project_type_id any'=> $Project->type_id() ) : () ),
      # FIXME
      ( $$specs{'PrintingType'.$qty_index} eq 'Digital' ? ( digital=>1 ) : () ),
      order		=>	'minimum_order',
    );
    if ( $qty_index ) {
      if ($$specs{'hdnSuppliedStockWidth'.$qty_index}) {
        $params{width} = $$specs{'hdnSuppliedStockWidth'.$qty_index};
        $params{type}	= $$specs{'StockType'.$qty_index} if $$specs{'StockType'.$qty_index};
        #$params{type}	= $$specs{StockType} if $$specs{StockType};
        if ( $params{type} ne 'Roll' ) {
          $params{height} = $$specs{'hdnSuppliedStockHeight'.$qty_index};
        } # end if
      }
    } # end if
    my @Papers = openprint::Paper->find( %params );
    if ( !@Papers ) {
      $log->debug("Didn't find specific paper $params{width} x $params{height} $$specs{StockType} type: " . $$specs{'StockType'.$qty_index});
      delete $params{width};
      delete $params{height};
      @Papers = openprint::Paper->find( %params );
    } # end if
    if ( !@Papers ) {
      $openprint::log->warn("No papers found for brand($$specs{ddmStockBrand}) finish($$specs{ddmStockFinish}) color($$specs{ddmStockColour}) weight($$specs{ddmStockWeight})");
      $Paper = new openprint::Paper();
      my @StockOptions = misc::trim(split (',', $openprint::config{$Project->Type()->name().'StockOptions'} )) if $Project;;
      @StockOptions = misc::trim(split (',', $openprint::config{StockOptions} )) if ! @StockOptions;
      @StockOptions = ( 'Brand','Finish','Colour','Weight' ) if ! @StockOptions;
      foreach my $option ( @StockOptions ) {
        my $lc_option = lc $option;
        $Paper->$lc_option( $$specs{"ddmStock$option"} );
      } # end foreach
      $Paper->calliper( $$specs{txtSpecificStockCalliper} );
      $Paper->start_width( $$specs{"hdnSuppliedStockWidth$qty_index"} );
      $Paper->start_height( $$specs{"hdnSuppliedStockHeight$qty_index"} );
      if ( $qty_index ) {
        $Paper->width( $$specs{'StockWidth'.$qty_index} );
        $Paper->height( $$specs{'StockHeight'.$qty_index} );
      } else {
        $Paper->width( $$specs{hdnSuppliedStockWidth} );
        $Paper->height( $$specs{hdnSuppliedStockHeight} );
      } # end if
      $Paper->doublesided( $$specs{CustomSheetDoubleSided} );
      $Paper->gsm( $$specs{txtStockGSM} ) if $$specs{txtStockGSM};
      $Paper->type( $$specs{'StockType'.$qty_index} ) if $$specs{'StockType'.$qty_index};
      $Paper->type( $$specs{StockType} ) if $$specs{StockType};

      $Paper->grade( $$specs{StockGrade});

      $$Paper{Price} = $$specs{CustomStockPrice};
      $$Paper{Units} = $$specs{CustomStockPriceUnits};
      $Paper->basis_width( $$specs{basis_width} ) if $$specs{basis_width};
      $Paper->basis_height( $$specs{basis_height} ) if $$specs{basis_height};
      $Paper->basis_mweight( $$specs{basis_mweight} ) if $$specs{basis_mweight};
      $Paper->score_required( $Paper->calliper() > 0.008 );
      $Paper->mweight( $$specs{'txtMWeight'.$qty_index} );
      @Papers = ( $Paper );
    } elsif ( $qty_index ) {
      my $Press = openprint::Equipment->find_one(strid=>$$specs{"ddmPress$qty_index"}) if $qty_index and $$specs{"ddmPress$qty_index"};
      foreach my $P ( @Papers ) {
        if ( $Press and ( my $Stock_Setting = $Press->Stock_Setting( $P ) ) ) {
          next if $Stock_Setting->grain() eq 'Dont Use';
        } # end if
        if ( ! $$specs{'StockQuantity'.$qty_index} ) {
          $$specs{'StockQuantity'.$qty_index} = $$specs{'txtPressSheetQty'.$qty_index};
          $$specs{'StockQuantity'.$qty_index} =~ s/\D//g;
        } # end if
        if ( $$specs{'StockQuantity'.$qty_index} and ( $$specs{'StockQuantity'.$qty_index} < $P->minimum_order() ) ) {
          $openprint::log->debug("Paper no good due to minimum order. Need " . $$specs{'StockQuantity'.$qty_index} . ' have ' . $P->minimum_order() ) if $debug;
          next;
        } # end if
        $Paper = $P;
        last;
      } # end foreach
    } else {
      $Paper = $Papers[0];
    } # end if
    if ( (!$Paper) and @Papers ) {
      $log->debug('No paper found matching minimum_order want '.$$specs{'StockQuantity'.$qty_index});
      foreach my $P ( @Papers ) {
        $log->debug($P->id_string());
      } # end foreach P
      $Paper = shift @Papers;
    } # end if

		if ( !$Paper ) {
$log->debug("No paper found");
			$Paper = new openprint::Paper();
		} # end if

		if ( $$specs{rdbSuppliedStock} eq 'Y' and ! $Paper->supplied() ) {
			$Paper->supplied(1);
		} # end if
	} # end if
	if ( $qty_index and (defined $$specs{'OverrideStockPrice'.$qty_index} ) and ( $$specs{'OverrideStockPrice'.$qty_index} eq 'Y' ) ) {
		$openprint::log->warn('Override price: ' . $$specs{'StockPrice'.$qty_index} );
		$$Paper{Price} = $$specs{'StockPrice'.$qty_index};
	} # end if

	my $Supplied = $Paper;
	$Paper = $Paper->clone();
$openprint::log->debug($Paper->to_string() );
	if ( $qty_index ) {
    #FIXME Whay?
    # So... if loading need to check that it fits the size.... but if we are loading by id.... then we don't need to do this... maybe test the impact of this code.
		if ( 
			( ( $$Paper{width} != $$specs{'StockWidth'.$qty_index} ) or ($$Paper{type} eq 'Sheet' and $$Paper{height} != $$specs{'StockHeight'.$qty_index} ) )
			and
			( ( $$Paper{height} != $$specs{'StockWidth'.$qty_index} ) or ($$Paper{type} eq 'Sheet' and $$Paper{width} != $$specs{'StockHeight'.$qty_index} ) )
		   ) {
         #Carp::cluck("Custom size $$specs{'StockWidth'.$qty_index}x$$specs{'StockHeight'.$qty_index}");
$openprint::log->debug("Custom size $$Paper{width}x$$Paper{height} => $$specs{'StockWidth'.$qty_index}x$$specs{'StockHeight'.$qty_index}");
			$$Paper{Supplied} = $Supplied;
			if ( ! $Supplied->start_width() ) {
        $openprint::log->debug("No start width?");
				$Supplied->width( $$specs{'StockWidth'.$qty_index} );
				$Supplied->start_width( $Supplied->width() );
			} 

			if ( ! $Paper->start_width() ) {
				$Paper->start_width( $Paper->width() );
				$Paper->width( $$specs{'StockWidth'.$qty_index} );
			} elsif ( $Paper->width() >= $$specs{'StockWidth'.$qty_index} ) {
				$Paper->width( $$specs{'StockWidth'.$qty_index} );
			} else {
				$log->warn('Unsuitable Stock' . $Paper->to_string() . ' desired: ' . $$specs{'StockWidth'.$qty_index} . 'x' . $$specs{'StockHeight'.$qty_index});
				return new openprint::Paper();
			} # end if

			if ( $Paper->type() ne 'Roll' ) {
				if ( ! $Paper->start_height() ) {
#$openprint::log->debug("Setting start height");
					$Paper->start_height( $$specs{'StockHeight'.$qty_index} );
					$Paper->height( $$specs{'StockHeight'.$qty_index} );
				} elsif ( $Paper->height() >= $$specs{'StockHeight'.$qty_index} ) {
					$Paper->height( $$specs{'StockHeight'.$qty_index} );
				} else {
					$log->warn('Unsuitable Stock due to height');
					return new openprint::Paper();
				} # end if
			
				if ( $Paper->width() and $Paper->height() and $Paper->start_width() and $Paper->start_height() ) {
					$Paper->mweight($Paper->mweight()/( ($Paper->start_width()/$Paper->width())*($Paper->start_height()/$Paper->height())));
				} # end if
			} # end if ! Roll
			$Paper->minimum_order( $$specs{minimum_order} * $Paper->factor() );
			$Paper->sheets_per_package( $$specs{sheets_per_package} * $Paper->factor() );
		} # end if
	} # end if qty_index
	return $Paper;

} # end sub load_from_signature

sub grain_direction {
	my $self = shift;
	if ( @_ ) {
		$$self{grain_direction} = $_[0];
	} # end if
	if ( ! $$self{grain_direction} ) {
# Default to second measurement
		$$self{grain_direction} = 'height';
	} # end if

	return $$self{grain_direction};
} # end sub grain_direction

sub doublesided {
	my $self = shift;
	if ( @_ ) {
		$$self{doublesided} = shift;
	} # end if
	return 'Y' if ( $$self{doublesided} eq 'Y' );
	return 'N' if ( $$self{doublesided} eq 'N' );
	return $$self{doublesided};

} # end sub doublesided

sub area {
	my $self = shift;
	return $$self{width} if ! $$self{height};
	return $$self{width}*$$self{height};
}

sub gsm_to_mweight {
	my ( $gsm ) = @_;

	my $wpsi = $gsm/703064.5;
	return sprintf('%.0f', $wpsi * 25 * 38 * 1000);
} # end sub gsm_to_mweight

sub gsm_to_weight {
	my ( $gsm ) = @_;
	my $wpsi = $gsm/703064.5;
	return sprintf('%.0f', $wpsi * 25 * 38 * 500 );
} # end sub gsm_to_weight

sub start_area {
	my $self = shift;
	return $$self{width} * $$self{height} if ! ( $$self{start_width} and $$self{start_height} );
	return $$self{start_width} if ! $$self{start_height};
	return $$self{start_width}*$$self{start_height};
}

sub is_cut {
	if ( $_[0]{start_width} and $_[0]{start_height} ) {
		return 1 if ( $_[0]{start_width} != $_[0]{width} or $_[0]{start_height} != $_[0]{height} );
	} # end if
	return 0;	
} # end sub is_cut

# Basis MWEight is the source sheet and mweight/gsm may not be calculable from it.
# We should not use wpsi as a basis for auto calculation.
sub basis_mweight {
	my $self = shift;
	if ( @_ ) {
		$$self{basis_mweight} = $_[0] ? $self->transform(basis_mweight=>shift) : $_[0];
	} # end if
	if ( ! $$self{basis_mweight} ) {
    if ( $self->weight() and (( $$self{weight} =~ /(\d+)lb/i ) or ( $$self{weight} =~ /(\d+)#/i ))) {
      $$self{basis_mweight} = 2*$1;
$openprint::log->debug("calcing basis_mweight from weight: $$self{basis_mweight} = $$self{weight} =~ 2*$1");
    } elsif ($$self{mweight} and $self->type() eq 'Sheet' and $$self{width} and $$self{height}) {
			$$self{basis_mweight} = Math::Round::nearest(1, 1000*($self->basis_width() * $self->basis_height()) * (($$self{mweight} / 1000)/($$self{width}*$$self{height})));
      $openprint::log->debug("calcing basis_mweight from mweight: $$self{basis_mweight} = ($$self{basis_width} * $$self{basis_height}) * (($$self{mweight} / 1000)/($$self{width}*$$self{height}))");

		} elsif ($$self{id}) {
			#$$self{basis_mweight} = 'Unknown';
			$openprint::log->error('Unable to calculated basis_mweight'.$$self{id}." weight was ".(defined $$self{weight} ? $$self{weight} : 'undef'));
		} # end if
	} # end if
	return $$self{basis_mweight};
} # end sub basis_mweight

sub basis_width {
	my ( $self, $width ) = @_;
	if ( defined $width ) {
		$width =~ s/[^\d\.]//g;
		$$self{basis_width} = $width;
	} # end if
	if ( ! $$self{basis_width} ) {
		if ( $self->is_cover() ) {
			$$self{basis_width} = 20;
		} elsif ( $self->is_bond() or $self->is_envelope() ) {
			$$self{basis_width} = 17;
    } elsif ($self->is_index()) {
      $$self{basis_width} = 25.5;
    } elsif ($self->is_tag()) {
      $$self{basis_width} = 24;
    } elsif ($self->is_bristol()) {
      $$self{basis_width} = 22.5;
		} else {
			$$self{basis_width} = 25;
		} # end if
	} # end if
	return $$self{basis_width};
} # end sub basis_width

sub basis_height {
	my ( $self, $height ) = @_;
	if ( defined $height ) {
		$height =~ s/[^\d\.]//g;
		$$self{basis_height} = $height;
	} # end if
	if ( ! $$self{basis_height} ) {
		if ( $self->is_cover() ) {
			$$self{basis_height} = 26;
		} elsif ( $self->is_bond() or $self->is_envelope() ) {
			$$self{basis_height} = 22;
    } elsif ($self->is_index()) {
			$$self{basis_height} = 30.5;
    } elsif ($self->is_tag()) {
			$$self{basis_height} = 36;
    } elsif ($self->is_bristol()) {
			$$self{basis_height} = 28.5;
		} else {
			$$self{basis_height} = 38;
		} # end if
	} # end if
	return $$self{basis_height};
} # end sub basis_height

sub sheet_weight {
	return $_[0]{width} * $_[0]{height} * $_[0]->wpsi();
} # end sub sheet_weight

sub start_sheet_weight {
	my ( $self ) = @_;
	return $$self{start_width} * $$self{start_height} * $self->wpsi();
} # end sub start_sheet_weight

sub units {
  my $self = shift;
  my $type = $self->type();
	return ($type eq 'Roll' ? 'lb' : 'sheet') . ( (@_ and $_[0] == 1) ? '' : 's' );
} # end sub units

sub types {
  my $type = $_[0]->type();
  return ' '.lc($type).( $_[1] == 1 ? '' : 's' );
} # end sub types

sub type {
  my $self = shift;
  $$self{type} = shift if @_;
  return 'Sheet' if !$$self{type};
  return $$self{type};
}

sub Supplied {
	my ( $self ) = @_;
	if ( ! $$self{Supplied} ) {
my ( $caller, undef, $line ) = caller;
$openprint::log->error("POpulating SUPLIED from $caller:$line");
		my $Supplied = $self->clone();
		$$Supplied{width} = $$self{start_width} ? $$self{start_width} : $$self{width};
		$$Supplied{height} = $$self{start_height} ? $$self{start_height} : $$self{height};
		delete $$Supplied{to_string};
		delete $$Supplied{id_string};
		$Supplied->mweight(0); # force recalc
		$$self{Supplied} = $Supplied;
	} # end if
	return $$self{Supplied};
} # end sub Supplied

sub long {
	my ( $self ) = @_;
	return $$self{width} > $$self{height} ? 'width' : 'height';
}

sub short {
	my ( $self ) = @_;
	return $$self{width} > $$self{height} ? 'height' : 'width';
}

sub start_width {
	if ( @_ > 1 ) {
		$_[0]{start_width} = $_[1];
	} 
	return $_[0]{start_width};
} # end sub start_width

sub start_height {
	if ( @_ > 1 ) {
		$_[0]{start_height} = $_[1];
	} 
	return $_[0]{start_height};
} # end sub start_height

sub init_cache {
	openprint::Manufacturer->find();
    openprint::StockBrand->find();
    openprint::StockFinish->find();
    openprint::StockColour->find();
    openprint::StockWeight->find();
    openprint::StockQuality->find();
    openprint::StockMaterial->find();
}

sub link_to {
  my $self = shift;
  my $text = @_ ? shift : $self->to_string();

	if ($openprint::session{user_type} eq 'A') {
	  return '<a href="/administrator/stock/stock.html?stock_id='.$$self{id}.'">'.$text.'</a>';
  } elsif ( $openprint::variable{uri} and ( $openprint::variable{uri} =~ /administrator/ ) ) {
	  return '<a href="/administrator/stock/stock.html?stock_id='.$$self{id}.'">'.$text.'</a>';
	} elsif ($openprint::session{user_type} eq 'E') {
	  return '<a href="/employee/inventory/paper_details.html?paper_id='.$$self{id}.'">'.$text.'</a>';
	} # end if
} # end sub link_to

sub sort {
	sort { 
		foreach my $option ( 'brand', 'finish', 'colour','weight' ) {
			return $a->$option() cmp $b->$option() if $a->$option() ne $b->$option();
		} # end foreach option
		foreach my $option ( 'width', 'height' ) {
			return $a->$option() <=> $b->$option() if $a->$option() != $b->$option();
		} # end foreach option
		
	} @_;
} # end sub sort

sub Unit_Of_Measure_Purchase {
	if ( $_[0]{type} eq 'Sheet' ) {
		return 'M';
	} else {
		return 'CWT';
	} # end if
} # end sub  Unit_Of_Measure_Purchase
sub Unit_Of_Measure_Costing {
	if ( $_[0]{type} eq 'Sheet' ) {
		return 'M';
	} else {
		return 'CWT';
	} # end if
} # end sub  Unit_Of_Measure_Costing

sub Supplier {
	return new openprint::Company( $_[0]{supplier_id} );
} # end sub Supplier

sub waste {
	my $area_factor = int($_[0]->start_width() / $_[0]->width()) + int($_[0]->start_height()/$_[0]->height() );
	return $_[0]->start_area() - ($area_factor*$_[0]->area());

	# Remove the integer part
	#$area_factor =~ s/.*\.//;
	#return $area_factor;
}

sub Unit_Cost {
	my $self = shift;
	my $Price = $self->get_price( service=>'Material',weight=>1);
	if( ! $Price ) {
		my @SC = openprint::SkidContent->find(paper_id=>$$self{id});
		foreach my $SC ( @SC ) {
			if ( $SC->cost() ) {
			
				return $SC->cost();
			} # en dif
		} # end foreach
	} # end if Price
	return $$Price{'100lb Cost'};
}
	
sub printing_types {
	my ( $self, $Project, $qty_index ) = @_;
	my @types;
	
	foreach my $sig_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
		foreach my $q_index ( $qty_index ? ( $qty_index ) : $Project->quantity_indexes() ) {
			next if ! $$sig_specs{"txtImposition$q_index"};
			push @types, $$sig_specs{"PrintingType$q_index"};
		}
	} # end foreach
$openprint::log->debug( "Types @types for " . $self->to_string() );
	return sets::union( @types );
}

sub check {
	my $Paper = shift;
	my $Copy = $Paper->clone();

	my @results;
  if ( abs( POSIX::ceil($Paper->gsm()) - POSIX::ceil($Copy->gsm(undef)) ) - 3 > 0 ) {
		push @results, "may have invalid gsm current:$$Paper{gsm} != calculated:$$Copy{gsm}";
  }

  $Copy = $Paper->clone();
  if ( $Paper->type() eq 'Envelope') {
    # mweight should be greater than calculated
    if ( POSIX::ceil($Paper->mweight()) - POSIX::ceil($Copy->mweight(undef)) < -1 ) {
      $openprint::log->debug("$$Paper{mweight} - $$Copy{mweight} = " . abs(POSIX::ceil($Paper->mweight()) - POSIX::ceil($Copy->mweight(undef))) );
      push @results, "may have invalid mweight current:$$Paper{mweight} ! >= calculated:$$Copy{mweight}";
    }
  } else {
    if ( abs(POSIX::ceil($Paper->mweight()) - POSIX::ceil($Copy->mweight(undef))) > 1 ) {
      $openprint::log->debug("$$Paper{mweight} - $$Copy{mweight} = " . abs(POSIX::ceil($Paper->mweight()) - POSIX::ceil($Copy->mweight(undef))) );
      push @results, "may have invalid mweight current:$$Paper{mweight} != calculated:$$Copy{mweight}";
    }
	}
  $Copy = $Paper->clone();
  if ( abs( POSIX::ceil($Paper->basis_mweight()) - POSIX::ceil($Copy->basis_mweight(undef)) ) -1 > 0 ) {
    push @results, "may have invalid basis weight current:$$Paper{basis_mweight} != calculated:$$Copy{basis_mweight}";
	}
	if ( $Paper->is_cover()
			and (
				($Paper->basis_width() != 20) 
				or 
				($Paper->basis_height() != 26)
				) 
		 ) {
$openprint::log->debug("basis: " . $Paper->basis_width() . 'x' . $Paper->basis_height());
		push @results, 'may have wrong basis size '.$Paper->basis_width() . 'x' . $Paper->basis_height().'. Should probably be 20x26' .
ssi::button('fix'.$$Paper{id}, { onclick=>q`set_basis_dimensions('20','26');`, text=>'Fix' } );
;
	}
	if ( $Paper->is_bond()
			and (
				($Paper->basis_width() != 17) 
				or 
				($Paper->basis_height() != 22)
				) 
		 ) {
$openprint::log->debug("basis: " . $Paper->basis_width() . 'x' . $Paper->basis_height());
		push @results, 'may have wrong basis size '.$Paper->basis_width() . 'x' . $Paper->basis_height().'. Should probably be 17x22';
	}
  if ( $Paper->is_envelope() 
			and (
				($Paper->basis_width() != 17) 
				or 
				($Paper->basis_height() != 22)
				) 
  ) {
$openprint::log->debug("basis: " . $Paper->basis_width() . 'x' . $Paper->basis_height());
		push @results, 'may have wrong basis size '.$Paper->basis_width() . 'x' . $Paper->basis_height().'. Should probably be 17x22';
  }
  if ( ( $Paper->finish() =~ /1 side/i ) and ( $Paper->c1sc2s() ne 'C1S') ) {
    push @results, 'appears to be C1S, but is marked C2S.';
  }
	if ( $Paper->weight() =~ /(\d+) *lb/i or $Paper->weight() =~ /(\d+) *#/) {
		if ( int($Paper->basis_mweight()) < (2*$1-1) or int($Paper->basis_mweight()) > (2*$1+1) ) {
			push @results, 'may have wrong basis weight ('.int($Paper->basis_mweight()).'. Should probably be '.2*$1;
		}
	}
  #my $old_wpsi = 1*$$Paper{wpsi};

  #if ( $old_wpsi ne $Paper->wpsi(undef) ) {
  #push @results, "invalid value for wpsi $old_wpsi should maybe be $$Paper{wpsi}";
  #}
	if ( $Paper->calliper() < 0.002 ) {
			push @results, "calliper $$Paper{calliper}  appears to be too low.";
	}
  foreach my $field (qw(Brand Finish Colour Weight)) {
    my $lc_field = lc $field;
    my $obj = $Paper->$field();
    if ($Paper->$lc_field() ne $obj->name()) {
      push @results, "discrepancy in stock $field $$Paper{$lc_field} != $$obj{name}";
    }
  }

	return join('<br/>', @results);
} # end sub check

sub is_cover {
  my $Paper = shift;
  return 
  (
    $Paper->brand() =~ /cover/i
      or
    $Paper->brand() =~ /board/i
      or
    $Paper->finish() =~ /cover/i
      or 
    $Paper->weight() =~ /cover/i
  );
}

sub is_bond {
	my $Paper = shift;
	return 
			($Paper->brand() =~ /bond/i
			 or
			$Paper->finish() =~ /bond/i
			or 
			$Paper->weight() =~ /bond/i);
}
sub is_index {
	my $Paper = shift;
	return 
			($Paper->brand() =~ /index/i
			 or
			$Paper->finish() =~ /index/i
			or 
			$Paper->weight() =~ /index/i);
}
sub is_tag {
	my $Paper = shift;
	return 
			($Paper->brand() =~ /tag/i
			 or
			$Paper->finish() =~ /tag/i
			or 
			$Paper->weight() =~ /tag/i);
}
sub is_bristol {
	my $Paper = shift;
	return 
			($Paper->brand() =~ /bristol/i
			 or
			$Paper->finish() =~ /bristol/i
			or 
			$Paper->weight() =~ /bristol/i);
}

sub is_envelope {
	my $Paper = shift;
	return (
    $$Paper{type} eq 'Envelope'
      or
    $Paper->brand() =~ /envelope/i
      or
    $Paper->finish() =~ /envelope/i
      or 
    $Paper->weight() =~ /envelope/i
  );
}

sub is_fsc {
	my $Paper = shift;
	return $$Paper{fsc_code} || ($Paper->brand() =~ /fsc/i) || ($Paper->finish() =~ /fsc/i);
}

sub destroy {
  my $self = shift;
  my $error;
  my $ac = sql::start_transaction( $openprint::dbh );
  foreach (
    openprint::PaperPrice->find( paper_id=>$$self{id} ),
    openprint::PaperInventory->find( paper_id=>$$self{id} ),
    openprint::PaperAllocation->find( paper_id=>$$self{id} ),
  ) {
    $error .= $_->destroy();
    if ( $error ) {
      $openprint::dbh->rollback();
      return $error;
    } # end if
  } # end foreach
  sql::execute(undef,undef, 'DELETE FROM tbl_paper_recommendations WHERE lngPaperIndex=?', $$self{id});
  #sql::execute(undef,undef, 'DELETE FROM inventory_check_entries WHERE paper_id=?', $$self{id});
  #sql::update(undef,undef, 'manifest_content_types', ['paper_id=?', $$self{id}], paper_id=>undef);
  $error .= $self->SUPER::destroy();
  sql::end_transaction( $openprint::dbh, $ac );
  return $error;
} # end sub destroy

sub grade {
  my $self = shift;
  $$self{grade} = shift if @_;
  if (!$$self{grade}) {
    #1	=>	'1 Gloss-coated stock',
    #2	=>	'2 Matte-coated stock',
    #3	=>	'3 Gloss-coated, web stock', 
    #4	=>	'4 Uncoated, white stock', 
    #5	=>	'5 Uncoated, yellow stock'
    if ($self->finish() =~ /gloss/i) {
      if ($self->type() eq 'Roll') {
        return $$self{grade} = 3;
      } else {
        return $$self{grade} = 1;
      }
    } elsif ($self->finish() =~ /matte/i or $self->finish() =~ /silk/i) {
      return $$self{grade} = 2;
    } elsif ($self->finish() =~ /uncoated/i) {
      return $$self{grade} = 4;
    }
    if ($self->brand() =~ /gloss/i) {
      if ($self->type() eq 'Roll') {
        return $$self{grade} = 3;
      } else {
        return $$self{grade} = 1;
      }
    } elsif ($self->brand() =~ /matte/i or $self->brand() =~ /silk/i) {
      return $$self{grade} = 2;
    } elsif ($self->brand() =~ /uncoated/i) {
      return $$self{grade} = 4;
    }

  } # end if !grade
  return $$self{grade};
}

sub taxexempt1 {
}
sub taxexempt2 {
}
1;
__END__
