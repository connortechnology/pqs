ALTER table ship_address add column shipnum int;
ALTER table tbl_addresses add column instructions text;
ALTER table tbl_addresses add column shipname text;

Update tbl_addresses SET shipname = strcompanyname;

alter table categories add column productinfo text;

