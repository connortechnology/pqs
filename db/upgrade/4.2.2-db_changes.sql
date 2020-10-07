
alter table tbl_project_contents add column price_override decimal(10,2);

alter table ship_address add column price decimal(10,2);
alter table ship_address add qty int;

alter table tbl_configuration add column label text;
alter table tbl_configuration add column category text;
alter table tbl_configuration add column sortval int;

INSERT into tbl_configuration values ( 'ShippingMarkup',20,  'Default Markup', 'SHIPPING', 10 ); 
INSERT into tbl_configuration values ( 'CompanyName','SHERWOOD PRINTERS',  'Shipping From Company Name', 'SHIPPING', 20 ); 
INSERT into tbl_configuration values ( 'Address1','240 Brunel Road',  'Address 1', 'SHIPPING', 30 ); 
INSERT into tbl_configuration values ( 'Address2','',  'Address 2', 'SHIPPING', 40 );
INSERT into tbl_configuration values ( 'PostalCode','L4Z1T5',  'Postal Code', 'SHIPPING', 50 );
INSERT into tbl_configuration values ( 'CountryCode','CA',  'Country Code', 'SHIPPING', 60 ); 
INSERT into tbl_configuration values ( 'Phone','9055011296',  'Phone', 'SHIPPING', 70 ); 
INSERT into tbl_configuration values ( 'Attention','Manoj Sheth',  'Attention', 'SHIPPING', 80 ); 
INSERT into tbl_configuration values ( 'Email','info\@sherwoodprinters.com',  'Email', 'SHIPPING', 90 ); 
INSERT into tbl_configuration values ( 'City','MISSISSAUGA',  'City', 'SHIPPING', 100 ); 
INSERT into tbl_configuration values ( 'ProvinceCode','ON',  'Province Code', 'SHIPPING', 110 ); 
