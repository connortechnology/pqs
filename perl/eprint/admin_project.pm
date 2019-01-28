package eprint::admin_project;
use strict;

use Apache2::Const qw(:common);
use eprint::docket;
use eprint::project;
use eprint::print;
use sql ();

sub view_project_for_rfq {
    my ($r, $log, $dbh, $variable) = @_;
    my $pid = $r->param('ProjectIndex');

    return SERVER_ERROR unless $pid;

    # Populate $variable with the header information and all the display
    # project service and material pricing.   
    $variable->{HeaderInfo} = eprint::docket::header_info($log, $dbh, $pid);
    eprint::print::display_project( $log, $dbh, $variable, $pid );

    # Create a checkbox for each service keyed to it's ID for use in the
    # "Request for Quote" (RFQ) form.
    for my $cat (@{ $variable->{categories} }) {
        for my $s (@{ $cat->{services} }) {
            # The only control each service gets is an HTML checkbox.
            $s->{controls} = [ { html => 
                  qq{ <input type="checkbox" name="$s->{id}-info_only" value="1" />}
               .  qq{<input type="checkbox" name="rfq" id="rfq-$s->{id}" checked='checked' value="$s->{id}" />}
            }];
        }
    }
    
	$variable->{flags}{can_edit} = 1;
    $$variable{is_quoted_or_ordered} = 1;
    return OK;
}


sub template_services_import_export {
    my ( $r, $log, $dbh, $variable ) = @_;

	my $status = 'Error: ';
    if ( $r->param('btnFunction') eq 'Import Services' ) {
        if ( $r->param('fileServices') ne '' ) {
			$_ = "DELETE FROM tbl_Template_Specifications";
			sql::sql_statement( $log, $dbh, $_ );
            my @content = misc::get_upload( $r, $log, 'fileServices' );
            my $csv = Text::CSV_XS->new();
            shift @content;
            foreach my $line ( @content ) {
                my $status = $csv->parse($line);
                my ( $project, $template, $service, $field, $value ) = misc::trim($csv->fields());

				my @params = (
						'strProjectType',	$project,
						'strTemplateType',	$template,
						'strService',		$service,
						'strName',			$field,
						'strValue',			$value 
						);
                my ($error) = sql::insert( $log, $dbh, 'tbl_Template_Specifications', @params );
#				$log->debug("** RESULTS: $error **");
#				if ( $error ne '' ) {
#					$log->debug("** Adding Error $error **");
#					$$variable{'ERRORS'} .= "Line Entry: " . $line . " <br> " . $error . " <br> <br> ";
#				} # end if
            } # for each
        } else {
            $log->warn( "No file given to upload." );
	} # end if
    
    } elsif ( $r->param('btnFunction') eq 'Export Services' ) {
    	my @header = ( 'Project Type', 'Template Type', 'Service ID', 'Field Name', 'Field Value');
	$_ = "SELECT strProjectType, strTemplateType, strService, strName, strValue FROM tbl_Template_Specifications ORDER BY strProjectType";
	my @data = sql::sql_statement ( $log, $dbh, $_ );

	misc::export_csv( $r, $log, $variable, 'project_templates_services.csv', \@header, \@data);
    } # end if
} # end sub template_import_export

sub template_import_export {
    my ( $r, $log, $dbh, $variable ) = @_;

	my $status = 'Error: ';

    if ( $r->param('btnFunction') eq 'Import Templates' ) {
        if ( $r->param('fileImport') ne '' ) {
			$_ = "DELETE FROM tbl_Project_Templates";
			sql::sql_statement( $log, $dbh, $_ );
            my @content = misc::get_upload( $r, $log, 'fileImport' );
            my $csv = Text::CSV_XS->new();
            shift @content;
            foreach my $line ( @content ) {
                my $status = $csv->parse($line);
                my ( $id, $name, $desc, $fwidth, $fheight, $panels, $width, $height, $single_hours, $double_hours, $services ) = $csv->fields();
                $id =~ s/^\s*(.*?)\s*$/$1/;
                $name =~ s/^\s*(.*?)\s*$/$1/;
                $desc =~ s/^\s*(.*?)\s*$/$1/;
                $services =~ s/^\s*(.*?)\s*$/$1/;

				my @params = (
						'strProjectType',		$id,
						'strTemplateType',		$name,
						'strDimensions',		$desc,
						'dblFinishedWidth',		$fwidth * 1,
						'dblFinishedHeight',	$fheight * 1,
						'dblFlatWidth',			$width * 1,
						'dblFlatHeight',		$height * 1,
						'lngPanels',			$panels * 1,
						'dblDesignHoursSingleSide',	$single_hours * 1,
						'dblDesignHoursDoubleSide',	$double_hours * 1
						);
                my ($error) = sql::insert( $log, $dbh, 'tbl_Project_Templates', @params );
				$log->debug("** TEMPLATE IMPORT: $error **");
#				if ( $error ne '' ) {
#					$log->debug("** Adding Error $error **");
#					$$variable{'ERRORS'} .= "Line Entry: " . $line . " <br> " . $error . " <br> <br> ";
#				} # end if
            } # for each
        } else {
            $log->warn( "No file given to upload." );
	} # end if

    } elsif ( $r->param('btnFunction') eq 'Export Templates' ) {
    	my @header = ( 'Project ID', 'Project Template', 'Drop Down Finished Dimensions', 'Finished Width', 'Finished Height', 'Panels', 'Flat Width', 'Flat Height', 'Design Hours 1 Sided', 'Design Hours 2 Sided');
	$_ = "SELECT strProjectType, strTemplateType, strDimensions, dblFinishedWidth, dblFinishedHeight, lngPanels, dblFlatWidth, dblFlatHeight, dblDesignHoursSingleSide, dblDesignHoursDoubleSide FROM tbl_Project_Templates ORDER BY strProjectType";
	my @data = sql::sql_statement( $log, $dbh, $_ );

	misc::export_csv( $r, $log, $variable, 'project_templates.csv', \@header, \@data );
	
    } # end if

} # end sub template_import_export

sub defaults_edit {
	my ( $r, $log, $dbh, $variable ) = @_;

	my $index = $r->param('ddmProjectType');

	if ( $r->param('btnFunction') eq 'Go' ) {
		if ( $r->param('txtGoProjectTypeID') ne '' ) {
			$_ = "SELECT lngIndex FROM tbl_ProjectTypes WHERE strID='".$r->param('txtGoProjectTypeID')."'";
			( $index ) = sql::sql_statement( $log, $dbh, $_ );
		} # end if
	} elsif ( $r->param('btnFunction') eq '<<' ) {
		$index = misc::nav_get_previous( $r, $log, $dbh, $index, 'lngIndex', 'tbl_ProjectTypes','','strID' );
	} elsif ( $r->param('btnFunction') eq '>>' ) {
		$index = misc::nav_get_next( $r, $log, $dbh, $index, 'lngIndex', 'tbl_ProjectTypes','','strID' );
	} elsif ( $r->param('btnFunction') eq 'Delete' ) {
		my $new_index = misc::nav_get_next( $r, $log, $dbh, $index, 'lngIndex', 'tbl_ProjectTypes','','strID' );
		sql::sql_statement( $log, $dbh, "DELETE FROM tbl_Paper_Recommendations WHERE lngProjectTypeIndex = '$index'" );
		sql::sql_statement( $log, $dbh, "DELETE FROM tbl_ProjectTypes WHERE lngIndex = '$index'" );
		$index = $new_index;
	} elsif ( $r->param('btnFunction') eq 'Save' ) {
		$_ = "DELETE from tbl_ProjectType_Defaults";
		sql::sql_statement( $log, $dbh, $_ );
		foreach my $spec ( $r->param() ) {
			$log->debug(" Checking: $spec ");
			if ( $spec =~ /txtID(\w*)/ ) {
				my $id = $r->param($spec);
				$log->debug(" Checking: $spec ID: $id : $1 ");
				$_ = "SELECT lngIndex FROM tbl_ProjectTypes WHERE strID = '$id'";
				my ($index) = sql::sql_statement( $log, $dbh, $_ );
				$index = 'NULL' if $index eq '';
				my $field = $r->param('txtName'.$1);
				my $value = $r->param('txtValue'.$1);
				sql::insert( $log, $dbh, 'tbl_ProjectType_Defaults', 'lngProjectTypeIndex',$index,'strFieldName',$field,'strDefaultValue',$value );
			} # end if
		} # foreach
	} elsif ( $r->param('btnFunction') eq 'Import' ) {
		my $error = '';
		if ( $r->param('fileImport') ne '' ) {
			my @content = misc::get_upload( $r, $log, 'fileImport' );
			my $csv = Text::CSV_XS->new();
			shift @content;
			my %cache = sql::sql_statement( $log, $dbh, "SELECT strID, lngIndex FROM tbl_ProjectTypes" );
			sql::sql_statement( $log, $dbh, "DELETE FROM tbl_ProjectType_Defaults" );
			foreach my $line ( @content ) {
				my $status = $csv->parse($line);
				my ( $id, $name, $value ) = misc::trim( $csv->fields() );
				$log->debug("ID: ($id), Name: ($name), Value: ($value)");
				if ( $id ne '' and ! $cache{$id} ) {
					$error .= "Project Type $id not found.<br>";
					next;
				} # end if
				sql::insert( $log, $dbh, 'tbl_ProjectType_Defaults', 
						'lngProjectTypeIndex', ( ( $id eq '' or $id eq 'All' ) ? 'NULL' : $cache{$id} ),
						'strFieldName', $name, 'strDefaultValue', $value  );
			} # end foreach

		} else {
			$log->warn( "No file given to upload." );
		} # end if
		if ( $error ne '' ) {
			return misc::error( $log, $dbh, $variable, 'Import errors.', $error );
		} # end if

	} elsif ( $r->param('btnFunction') eq 'Export' ) {
	    	my @header = ( 'Project Type ID', 'Field Name', 'Field Value');

		$_ = "SELECT (SELECT strID FROM tbl_ProjectTypes WHERE lngIndex=lngProjectTypeIndex) AS ID,strFieldName, strDefaultValue\n".
			"FROM tbl_ProjectType_Defaults\n".
			"ORDER BY ID, strFieldName";
		my @data = sql::sql_statement( $log, $dbh, $_ );

		misc::export_csv( $r, $log, $variable, 'project_defaults.csv', \@header, \@data );
	
	} # end if

	$_ = "SELECT (SELECT strID FROM tbl_ProjectTypes WHERE lngIndex=lngProjectTypeIndex) AS ID,strFieldName, strDefaultValue\n".
		"FROM tbl_ProjectType_Defaults\n".
		"ORDER BY ID, strFieldName";
	@{$$variable{'Defaults'}} = sql::sql_statement( $log, $dbh, $_ );

} # end sub defaults_edit

1;

