dm log 'clear';
dm lst 'clear';
dm log 'preview';

proc datasets library=work mt=data kill nolist;
quit;

libname adam "D:\Home\dev\cdisc_data_setup";

*=========================================================;
*This program creates adverse event table -soc and pt level
*counts;
*=========================================================;

proc sort data=adam.adsl out=adsl(keep=usubjid trtpn safety);
	by usubjid;
	where safety="Y";
run;

data adsl;
	set adsl;
	output;
	trtpn=4;
	output;
run;

data adsl;
	set adsl;
	output;
	if trtpn in (1,2) then do;
	trtpn=3;
	output;
	end;
run;


proc sort data=adam.adae out=adae;
	by usubjid;
	where trtemfl="Y";
run;

data adae;
	set adae;
	output;
	trtpn=4;
	output;
run;

data adae;
	set adae;
	output;
	if trtpn in (1,2) then do;
	trtpn=3;
	output;
	end;
run;


*================================================================================;
*get treatment totals into a dataset and into macro variables(for column headers);
*================================================================================;

proc sql;
	create table trttotal_pre as 
		select trtpn,
		count(distinct usubjid) as trttotal
		from adsl
		group by trtpn;
quit;

*create dummy dataset for treatement totals;

data dummy_pre;
	trttotal=0;
	do trtpn=0 to 4;
		output;
	end;
run;

*merge actual counts with dummt counts;

data trttotals;
	merge dummy_pre(in=a) trttotal_pre(in=b);
	by trtpn;
run;


*macro variables;
proc sql noprint;
	select count(distinct usubjid) into :n1 from adsl where trtpn=0;
	select count(distinct usubjid) into :n2 from adsl where trtpn=1;
	select count(distinct usubjid) into :n3 from adsl where trtpn=2;
	select count(distinct usubjid) into :n4 from adsl where trtpn=3;
	select count(distinct usubjid) into :n5 from adsl where trtpn=4;

quit;

%put number of subjects in trt1 &n1;
%put number of subjects in trt2 &n2;
%put number of subjects in trt3 &n3;
%put number of subjects in trt4 &n4;
%put number of subjects in trt5 &n5;

*=====================================================================================;

data ae_pre;
	set adae;
	if missing(aebodsys) then aebodsys="Not coded";
	if missing(aedecod) then aedecod="Not coded";
run;

proc sort data=ae_pre;
	by usubjid trtpn;
run;

proc sort data=adsl;
	by usubjid trtpn;
run;

data ae;
	merge ae_pre(in=a) adsl(in=b);
	by usubjid trtpn;
	if a and b;
run;

*================================================================;
*obtaining actual counts-for the table;
*================================================================;

*------------------------------;
*subject level count- top row;
*------------------------------;

proc sql noprint;
	create table sub_count as 
	select "Patients with atleast one AE" as label length=200,
	trtpn,
	count(distinct usubjid) as count 
	from ae where aefn=1
	group by trtpn;
quit;

*---------------------------------------;
*soc level counts;
*---------------------------------------;

proc sql noprint;
	create table soc_count as
		select aebodsys, trtpn,
		count(distinct usubjid) as count
		from ae where bodfn=1
		group by aebodsys,trtpn;
quit;

*--------------------------------------;
*preferred term level counts;
*--------------------------------------;

proc sql noprint;
	create table pt_count as 
		select aebodsys,aedecod,trtpn,
		count(distinct usubjid) as count
		from ae where decodfn=1
		group by aebodsys,aedecod,trtpn;
quit;

*---------------------------------;
*put all counts together;
*---------------------------------;

data counts;
	set sub_count soc_count pt_count;
run;

*=========================================================;
*create zero counts if an event is not present in a trt;
*=========================================================;

*get all the available soc-s and pt-s;

proc sort data=counts out=dummy_pre(keep=aebodsys aedecod label) nodupkey;
	by aebodsys aedecod label;
run;

*create a row for each treatment and severity;

data dummy;
	set dummy_pre;
	count=0;
	do trtpn=0 to 4;
			output;
	end;
run;

*merge dummy counts with actual counts;
proc sort data=dummy;
	by aebodsys aedecod label trtpn;
run;


proc sort data=counts out=counts2;
	by aebodsys aedecod label trtpn;
run;

data counts3;
	merge dummy(in=a) counts2(in=b);
	by aebodsys aedecod label trtpn;
run;

*---------------------------------------;
*obtain percentages;
*---------------------------------------;

*merge counts with trttotals dataset, to get denominator values(trt totals);

proc sort data=counts3;
	by trtpn;
run;

proc sort data=trttotals;
	by trtpn;
run;

data counts4;
	merge counts3(in=a) trttotals(in=b);
	by trtpn;
	if a;
run;

data counts4;
	set counts4;
	percent=round((count/trttotal*100),0.1);
	if count ne 0 then count_percent=put(count,3.)||" ("||put(percent,5.1)||")";
	else if count=0 then count_percent=put(count,3.);
run;

*---------------------------------------------;
*create the label column;
*---------------------------------------------;

data counts5;
	set counts4;
	if missing(aebodsys) and missing(aedecod) then label=label;
	else if not missing(aebodsys) and missing(aedecod) then label="  "|| strip(aebodsys);
	else if not missing(aebodsys) and not missing(aedecod) then label="    "||strip(aedecod);
run;

*====================================================;
*transpose to obtain treatment as columns;
*====================================================;

proc sort data=counts5;
	by aebodsys aedecod label ;
run;

proc transpose data=counts5 out=trans1 prefix=trt;
	by aebodsys aedecod label;
	var count_percent;
	id trtpn;
run;


data final;
	set trans1;
	keep aebodsys aedecod label trt0 trt1 trt2 trt3 trt4;
run;


*============================================================================;
*report generation;
*============================================================================;

title;
footnote;
options ps=48 ls=153 nonumber nodate;

proc report data=final nowd headline headskip missing spacing=0;
	columns ("" "-Period=Induction-" "" aebodsys aedecod label  trt0 ("" "Xanomeline" "" "--" trt1 trt2 trt3) trt4);
	define aebodsys/ order noprint;
	define aedecod/order noprint;
	define label /order "System Organ Class" "  Preferred Term" width=50;
	define trt0/"  Placebo" "  (N=%cmpres(&n1))" width=21  ;
	define trt1/"  50 mg" "  (N=%cmpres(&n2))" width=21 ;
	define trt2/ "  80 mg" "  (N=%cmpres(&n3))" width=21 ;
	define trt3/ "  Total" "  (N=%cmpres(&n4))" width=17 ;
	define trt4/"  Total" "  (N=%cmpres(&n5))" width=20 spacing=3;
	break after aebodsys/skip;

	compute before _page_;
		line @1 "Title1";
		line @1 "Title2";
		line @ 1 "";
		line @1 153*'-';
	endcomp;

	compute after _page_;
		line @1 153*'-';
		line @1 "Footnote1";
		line @1 "Footnote2";
		line @1 "Footnote3";
		line @1"";
	endcomp;
run;


