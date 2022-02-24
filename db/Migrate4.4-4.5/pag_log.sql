
drop table log;
create table log (
	ip text,
	session text,
	userid text,
	reqtime timestamp,
	page text,
	params text,
	pid int,
	oid int
);
