%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1997-2013. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%
%%
-module(asn1ct_constructed_per).

-export([gen_encode_sequence/3]).
-export([gen_decode_sequence/3]).
-export([gen_encode_set/3]).
-export([gen_decode_set/3]).
-export([gen_encode_sof/4]).
-export([gen_decode_sof/4]).
-export([gen_encode_choice/3]).
-export([gen_decode_choice/3]).

-include("asn1_records.hrl").
%-compile(export_all).

-import(asn1ct_gen, [emit/1,demit/1,get_record_name_prefix/0]).
-import(asn1ct_func, [call/3]).

%% ENCODE GENERATOR FOR SEQUENCE TYPE  ** **********


gen_encode_set(Erules,TypeName,D) ->
    gen_encode_constructed(Erules,TypeName,D).

gen_encode_sequence(Erules,TypeName,D) ->
    gen_encode_constructed(Erules,TypeName,D).

gen_encode_constructed(Erule,Typename,D) when is_record(D,type) ->
    asn1ct_name:start(),
    asn1ct_name:new(term),
    asn1ct_name:new(bytes),
    {ExtAddGroup,TmpCompList,TableConsInfo} =
	case D#type.def of
	    #'SEQUENCE'{tablecinf=TCI,components=CL,extaddgroup=ExtAddGroup0} ->
		{ExtAddGroup0,CL,TCI};
	    #'SET'{tablecinf=TCI,components=CL} ->
		{undefined,CL,TCI}
	end,

    CompList = case ExtAddGroup of
		   undefined ->
		       TmpCompList;
		   _ when is_integer(ExtAddGroup) ->
		       %% This is a fake SEQUENCE representing an ExtensionAdditionGroup
		       %% Reset the textual order so we get the right
		       %% index of the components
		       [Comp#'ComponentType'{textual_order=undefined}||
			   Comp<-TmpCompList]
	       end,
    case Typename of
	['EXTERNAL'] ->
	    emit([{next,val}," = ",
		  {call,ext,transform_to_EXTERNAL1990,
		   [{curr,val}]},com,nl]),
	    asn1ct_name:new(val);
	_ ->
	    ok
    end,
    case {Optionals = optionals(to_textual_order(CompList)),CompList,
	  is_optimized(Erule)} of
	{[],EmptyCL,_} when EmptyCL == {[],[],[]};EmptyCL == {[],[]};EmptyCL == [] -> 
	    ok;
	{[],_,_} ->
	    emit([{next,val}," = ",{curr,val},",",nl]);
	{_,_,true} ->
	    gen_fixoptionals(Optionals),
	    FixOpts = param_map(fun(Var) ->
					{var,Var}
				end,asn1ct_name:all(fixopt)),
	    emit({"{",{next,val},",Opt} = {",{curr,val},",[",FixOpts,"]},",nl});
	{_,_,false} ->
	    asn1ct_func:need({Erule,fixoptionals,3}),
	    Fixoptcall = ",Opt} = fixoptionals(",
	    emit({"{",{next,val},Fixoptcall,
		  {asis,Optionals},",",length(Optionals),
		  ",",{curr,val},"),",nl})
    end,
    asn1ct_name:new(val),
    Ext = extensible_enc(CompList),
    case Ext of
	{ext,_,NumExt} when NumExt > 0 ->
	    case extgroup_pos_and_length(CompList) of
		{extgrouppos,[]} -> % no extenstionAdditionGroup
		    ok;
		{extgrouppos,ExtGroupPosLenList} ->
		    ExtGroupFun = 
			fun({ExtActualGroupPos,ExtGroupVirtualPos,ExtGroupLen}) ->
				Elements = 
				    make_elements(ExtGroupVirtualPos+1,
						  "Val1",
						  lists:seq(1,ExtGroupLen)),
				emit([
				      {next,val}," = case [X || X <- [",Elements,
				      "],X =/= asn1_NOVALUE] of",nl,
				      "[] -> setelement(",
				      {asis,ExtActualGroupPos+1},",",
				      {curr,val},",",
				      "asn1_NOVALUE);",nl,
				      "_ -> setelement(",{asis,ExtActualGroupPos+1},",",
				      {curr,val},",",
				      "{extaddgroup,", Elements,"})",nl,
				      "end,",nl]),
				asn1ct_name:new(val)
			end,
		    lists:foreach(ExtGroupFun,ExtGroupPosLenList)
	    end,
	    asn1ct_name:new(tmpval),
	    emit(["Extensions = ",
		  {call,Erule,fixextensions,[{asis,Ext},{curr,val}]},
		  com,nl]);
	_ -> true
    end,
    EncObj =
	case TableConsInfo of
	    #simpletableattributes{usedclassfield=Used,
				   uniqueclassfield=Unique} when Used /= Unique ->
		false;
	    %% ObjectSet, name of the object set in constraints
	    %% 
	    %%{ObjectSet,AttrN,N,UniqueFieldName} -> %% N is index of attribute that determines constraint
	    #simpletableattributes{objectsetname=ObjectSet,
				   c_name=AttrN,
				   c_index=N,
				   usedclassfield=UniqueFieldName,
				   uniqueclassfield=UniqueFieldName,
				   valueindex=ValueIndex
				  } -> %% N is index of attribute that determines constraint
		{Module,ObjSetName} = ObjectSet,
		#typedef{typespec=#'ObjectSet'{gen=Gen}} =
		    asn1_db:dbget(Module, ObjSetName),
		case Gen of
		    true ->
			ObjectEncode = 
			    asn1ct_gen:un_hyphen_var(lists:concat(['Obj',AttrN])),
			El = make_element(N+1, asn1ct_gen:mk_var(asn1ct_name:curr(val))),
			ValueMatch = value_match(ValueIndex, El),
			emit([ObjectEncode," =",nl,
			      "  ",{asis,Module},":'getenc_",ObjSetName,"'(",
			      {asis,UniqueFieldName},", ",nl,
			      "  ",ValueMatch,"),",nl]),
			{AttrN,ObjectEncode};
		    false ->
			false
		end;
	    _  ->
		case D#type.tablecinf of
		    [{objfun,_}|_] ->
			%% when the simpletableattributes was at an outer
			%% level and the objfun has been passed through the
			%% function call
			{"got objfun through args","ObjFun"};
		    _ ->
			false
		end
	end,
    emit({"[",nl}),
    MaybeComma1 = 
	case Ext of
	    {ext,_Pos,NumExt2} when NumExt2 > 0 -> 
		call(Erule, setext, ["Extensions =/= []"]),
		", ";
	    {ext,_Pos,_} -> 
		call(Erule, setext, ["false"]),
		", ";
	    _ -> 
		""
	end,
    MaybeComma2 = 
	case optionals(CompList) of
	    [] -> MaybeComma1;
	    _ -> 
		emit(MaybeComma1),
		emit("Opt"),
		{",",nl}
	end,
    gen_enc_components_call(Erule,Typename,CompList,MaybeComma2,EncObj,Ext),
    emit({"].",nl}).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% generate decode function for SEQUENCE and SET
%%
gen_decode_set(Erules,Typename,D) ->
    gen_decode_constructed(Erules,Typename,D).

gen_decode_sequence(Erules,Typename,D) ->
    gen_decode_constructed(Erules,Typename,D).

gen_decode_constructed(Erule, Typename, #type{}=D) ->
    Imm0 = gen_dec_constructed_imm(Erule, Typename, #type{}=D),
    Imm = opt_imm(Imm0),
    asn1ct_name:start(),
    emit_gen_dec_imm(Imm),
    emit([".",nl,nl]).

opt_imm(Imm0) ->
    {Imm,_} = opt_imm_1(Imm0, unknown, []),
    Imm.

opt_imm_1([{imm,Imm0,F}|T], Al0, Acc) ->
    {Imm,Al} = asn1ct_imm:optimize_alignment(Imm0, Al0),
    opt_imm_1(T, Al, [{imm,Imm,F}|Acc]);
opt_imm_1([ignore|T], Al, Acc) ->
    opt_imm_1(T, Al, Acc);
opt_imm_1([{ignore,_}=H|T], Al, Acc) ->
    opt_imm_1(T, Al, [H|Acc]);
opt_imm_1([{safe,ignore}|T], Al, Acc) ->
    opt_imm_1(T, Al, Acc);
opt_imm_1([{safe,_}=H|T], Al, Acc) ->
    opt_imm_1(T, Al, [H|Acc]);
opt_imm_1([{group,G0}|T], Al0, Acc) ->
    {G,Al} = opt_imm_1(G0, Al0, []),
    opt_imm_1(T, Al, [{group,G}|Acc]);
opt_imm_1([Emit|T], _, Acc) when is_function(Emit, 1) ->
    opt_imm_1(T, unknown, [Emit|Acc]);
opt_imm_1([], Al, Acc) ->
    {lists:reverse(Acc),Al}.

emit_gen_dec_imm(L) ->
    emit_gen_dec_imm(L, "", []).

emit_gen_dec_imm([{ignore,Fun}|T], Sep, St0) ->
    St = Fun(St0),
    emit_gen_dec_imm(T, Sep, St);
emit_gen_dec_imm([{group,L}|T], Sep, St0) ->
    emit(Sep),
    St = emit_gen_dec_imm_group(L, St0),
    emit_gen_dec_imm(T, [com,nl], St);
emit_gen_dec_imm([{imm,Imm,Emit}|T], Sep, St0) ->
    emit(Sep),
    St = Emit(Imm, St0),
    emit_gen_dec_imm(T, [com,nl], St);
emit_gen_dec_imm([{safe,Item}|T], Sep, St) ->
    emit_gen_dec_imm([Item|T], Sep, St);
emit_gen_dec_imm([Emit|T], Sep, St0) ->
    emit(Sep),
    St = Emit(St0),
    emit_gen_dec_imm(T, [com,nl], St);
emit_gen_dec_imm([], _, _) -> ok.

emit_gen_dec_imm_group([H|T], St0) ->
    St = emit_gen_dec_group_item(H, St0),
    emit_gen_dec_imm_group(T, St);
emit_gen_dec_imm_group([], St) -> St.

emit_gen_dec_group_item({ignore,Fun}, St) ->
    Fun(St);
emit_gen_dec_group_item({imm,Imm,Fun}, St) ->
    Fun(Imm, St);
emit_gen_dec_group_item({safe,Item}, St) ->
    emit_gen_dec_group_item(Item, St);
emit_gen_dec_group_item(Emit, St) ->
    Emit(St).

gen_dec_constructed_imm(Erule, Typename, #type{}=D) ->
    {CompList,TableConsInfo} = 
	case D#type.def of
	    #'SEQUENCE'{tablecinf=TCI,components=CL} ->
		{add_textual_order(CL),TCI};
	    #'SET'{tablecinf=TCI,components=CL} ->
%%		{add_textual_order(CL),TCI}
		{CL,TCI} % the textual order is already taken care of
	end,
    Ext = extensible_dec(CompList),
    EmitExt = case Ext of
		  {ext,_Pos,_NumExt} ->
		      gen_dec_extension_value();
		  _ -> ignore
	      end,
    Optionals = optionals(CompList),
    EmitOpt = case Optionals of
		  [] ->
		      ignore;
		  [_|_] ->
		      gen_dec_optionals(Optionals)
	      end,
    ObjSetInfo =
	case TableConsInfo of
%%	    {ObjectSet,AttrN,N,UniqueFieldName} ->%% N is index of attribute that determines constraint
	    #simpletableattributes{objectsetname=ObjectSet,
				   c_name=AttrN,
				   usedclassfield=UniqueFieldName,
				   uniqueclassfield=UniqueFieldName,
				   valueindex=ValIndex} ->
%%		{AttrN,ObjectSet};
		F = fun(#'ComponentType'{typespec=CT})->
			    case {asn1ct_gen:get_constraint(CT#type.constraint,componentrelation),CT#type.tablecinf} of
				{no,[{objfun,_}|_R]} -> true;
				_ -> false
			    end
		    end,
		case lists:any(F,flat_complist(CompList)) of
		    true -> % when component relation constraint establish
			%% relation from a component to another components
			%% subtype component
			{{AttrN,{deep,ObjectSet,UniqueFieldName,ValIndex}},
			 UniqueFieldName,ValIndex};
		    false ->
			{{AttrN,ObjectSet},UniqueFieldName,ValIndex}
		end;
	    _ ->
		case D#type.tablecinf of
		    [{objfun,_}|_] ->
			{{"got objfun through args","ObjFun"},false,false};
		    _ ->
			{false,false,false}
		end
	end,
    {DecObjInf,_,_} = ObjSetInfo,
    EmitComp = gen_dec_components_call(Erule, Typename, CompList,
				       DecObjInf, Ext, length(Optionals)),
    EmitRest = fun({AccTerm,AccBytes}) ->
		       gen_dec_constructed_imm_2(Typename, CompList,
						 ObjSetInfo,
						 AccTerm, AccBytes)
	       end,
    [EmitExt,EmitOpt|EmitComp++[{safe,EmitRest}]].

gen_dec_constructed_imm_2(Typename, CompList,
			  ObjSetInfo, AccTerm, AccBytes) ->
    {_,UniqueFName,ValueIndex} = ObjSetInfo,
    case {AccTerm,AccBytes} of
	{[],[]} ->
	    ok;
	{_,[]} ->
	    ok;
	{[{ObjSet,LeadingAttr,Term}],ListOfOpenTypes} ->
	    DecObj = asn1ct_gen:un_hyphen_var(lists:concat(['DecObj',LeadingAttr,Term])),
	    ValueMatch = value_match(ValueIndex,Term),
	    {ObjSetMod,ObjSetName} = ObjSet,
	    emit([DecObj," =",nl,
		  "   ",{asis,ObjSetMod},":'getdec_",ObjSetName,"'(",
		  {asis,UniqueFName},", ",ValueMatch,"),",nl]),
	    gen_dec_listofopentypes(DecObj,ListOfOpenTypes,false)
    end,
    %% we don't return named lists any more   Cnames = mkcnamelist(CompList), 
    demit({"Result = "}), %dbg
    %% return value as record
    RecordName = record_name(Typename),
    case Typename of
	['EXTERNAL'] ->
	    emit({"   OldFormat={'",RecordName,
		  "'"}),
	    mkvlist(asn1ct_name:all(term)),
	    emit({"},",nl}),
	    emit(["   ASN11994Format =",nl,
		  "      ",
		  {call,ext,transform_to_EXTERNAL1994,
		   ["OldFormat"]},com,nl]),
	    emit("   {ASN11994Format,");
	_ ->
	    emit(["{{'",RecordName,"'"]),
	    %% CompList is used here because we don't want
	    %% ExtensionAdditionGroups to be wrapped in SEQUENCES when
	    %% we are ordering the fields according to textual order
	    mkvlist(textual_order(to_encoding_order(CompList),asn1ct_name:all(term))),
	    emit("},")
    end,
    emit({{curr,bytes},"}"}).

%% record_name([TypeName]) -> RecordNameString
%%  Construct a record name for the constructed type, ignoring any
%%  fake sequences that are used to represent an extension addition
%%  group. Such fake sequences never appear as a top type, and their
%%  name always start with "ExtAddGroup".

record_name(Typename0) ->
    [TopType|Typename1] = lists:reverse(Typename0),
    Typename = filter_ext_add_groups(Typename1, [TopType]),
    lists:concat([get_record_name_prefix(),
		  asn1ct_gen:list2rname(Typename)]).

filter_ext_add_groups([H|T], Acc) when is_atom(H) ->
    case atom_to_list(H) of
	"ExtAddGroup"++_ ->
	    filter_ext_add_groups(T, Acc);
	_ ->
	    filter_ext_add_groups(T, [H|Acc])
    end;
filter_ext_add_groups([H|T], Acc) ->
    filter_ext_add_groups(T, [H|Acc]);
filter_ext_add_groups([], Acc) -> Acc.

textual_order([#'ComponentType'{textual_order=undefined}|_],TermList) ->
    TermList;
textual_order(CompList,TermList) when is_list(CompList) ->
    OrderList = [Ix||#'ComponentType'{textual_order=Ix} <- CompList],
    [Term||{_,Term}<-
	       lists:sort(lists:zip(OrderList,
				    lists:sublist(TermList,length(OrderList))))];
	       %% sublist is just because Termlist can sometimes be longer than
	       %% OrderList, which it really shouldn't
textual_order({Root,Ext},TermList) ->
    textual_order(Root ++ Ext,TermList).

to_textual_order({Root,Ext}) ->
    {to_textual_order(Root),Ext};
to_textual_order(Cs) when is_list(Cs) ->
    case Cs of
	[#'ComponentType'{textual_order=undefined}|_] ->
	    Cs;
	_ ->
	    lists:keysort(#'ComponentType'.textual_order,Cs)
    end;
to_textual_order(Cs) ->
    Cs.

gen_dec_listofopentypes(_,[],_) ->
    emit(nl);
gen_dec_listofopentypes(DecObj,[{_Cname,{FirstPFN,PFNList},Term,TmpTerm,Prop}|Rest],_Update) ->

    asn1ct_name:new(tmpterm),
    asn1ct_name:new(reason),

    emit([Term," = ",nl]),

    N = case Prop of
	    mandatory -> 0;
	    'OPTIONAL' ->
		emit_opt_or_mand_check(asn1_NOVALUE,TmpTerm),
		6;
	    {'DEFAULT',Val} ->
		emit_opt_or_mand_check(Val,TmpTerm),
		6
	end,

    emit([indent(N+3),"case (catch ",DecObj,"(",
	  {asis,FirstPFN},", ",TmpTerm,", telltype,",{asis,PFNList},")) of",nl]),
    emit([indent(N+6),"{'EXIT', ",{curr,reason},"} ->",nl]),
    emit([indent(N+9),"exit({'Type not compatible with table constraint',",
	  {curr,reason},"});",nl]),
    emit([indent(N+6),"{",{curr,tmpterm},",_} ->",nl]),
    emit([indent(N+9),{curr,tmpterm},nl]),

    case Prop of
	mandatory ->
	    emit([indent(N+3),"end,",nl]);
	_ ->
	    emit([indent(N+3),"end",nl,
		  indent(3),"end,",nl])
    end,
    gen_dec_listofopentypes(DecObj,Rest,true).


emit_opt_or_mand_check(Val,Term) ->
    emit([indent(3),"case ",Term," of",nl,
	  indent(6),{asis,Val}," ->",{asis,Val},";",nl,
	  indent(6),"_ ->",nl]).

%% ENCODE GENERATOR FOR THE CHOICE TYPE *******
%% assume Val = {Alternative,AltType}
%% generate
%%[
%% ?RT_PER:set_choice(element(1,Val),Altnum,Altlist,ext),
%%case element(1,Val) of
%%    alt1 ->
%%	encode_alt1(element(2,Val));
%%    alt2 ->
%%	encode_alt2(element(2,Val))
%%end
%%].

gen_encode_choice(Erule,Typename,D) when is_record(D,type) ->
    {'CHOICE',CompList} = D#type.def,
    emit({"[",nl}),
    Ext = extensible_enc(CompList),
    gen_enc_choice(Erule,Typename,CompList,Ext),
    emit({nl,"].",nl}).

gen_decode_choice(Erules,Typename,D) when is_record(D,type) ->
    asn1ct_name:start(),
    asn1ct_name:new(bytes),
    {'CHOICE',CompList} = D#type.def,
    Ext = extensible_enc(CompList),
    gen_dec_choice(Erules,Typename,CompList,Ext),
    emit({".",nl}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Encode generator for SEQUENCE OF type


gen_encode_sof(Erule,Typename,SeqOrSetOf,D) when is_record(D,type) ->
    asn1ct_name:start(),
    {_SeqOrSetOf,ComponentType} = D#type.def,
    emit({"[",nl}),
    SizeConstraint = asn1ct_imm:effective_constraint(bitstring,
						     D#type.constraint),
    ObjFun =
	case D#type.tablecinf of
	    [{objfun,_}|_R] ->
		", ObjFun";
	    _->
		""
	end,
    gen_encode_length(Erule, SizeConstraint),
    emit({indent(3),"'enc_",asn1ct_gen:list2name(Typename),
	      "_components'(Val",ObjFun,", [])"}),
    emit({nl,"].",nl}),
    gen_encode_sof_components(Erule, Typename, SeqOrSetOf, ComponentType).


%% Logic copied from asn1_per_bin_rt2ct:encode_constrained_number
gen_encode_length(per, {Lb,Ub}) when Ub =< 65535, Lb >= 0 ->
    Range = Ub - Lb + 1,
    V2 = ["(length(Val) - ",Lb,")"],
    Encode = if
		 Range  == 1 ->
		     "[]";
		 Range  == 2 ->
		     {"[",V2,"]"};
		 Range  =< 4 ->
		     {"[10,2,",V2,"]"};
		 Range  =< 8 ->
		     {"[10,3,",V2,"]"};
		 Range  =< 16 ->
		     {"[10,4,",V2,"]"};
		 Range  =< 32 ->
		     {"[10,5,",V2,"]"};
		 Range  =< 64 ->
		     {"[10,6,",V2,"]"};
		 Range  =< 128 ->
		     {"[10,7,",V2,"]"};
		 Range  =< 255 ->
		     {"[10,8,",V2,"]"};
		 Range  =< 256 ->
		     {"[20,1,",V2,"]"};
		 Range  =< 65536 ->
		     {"[20,2,<<",V2,":16>>]"};
		 true ->
		     {call,per,encode_length,
		      [{asis,{Lb,Ub}},"length(Val)"]}
	     end,
    emit({nl,Encode,",",nl});
gen_encode_length(Erules, SizeConstraint) ->
    emit([nl,indent(3),
	  case SizeConstraint of
	      no ->
		  {call,Erules,encode_length,["length(Val)"]};
	      _ ->
		  {call,Erules,encode_length,
		   [{asis,SizeConstraint},"length(Val)"]}
	  end,
	  com,nl]).

gen_decode_sof(Erules,Typename,SeqOrSetOf,D) when is_record(D,type) ->
    asn1ct_name:start(),
    {_SeqOrSetOf,ComponentType} = D#type.def,
    SizeConstraint = asn1ct_imm:effective_constraint(bitstring,
						     D#type.constraint),
    ObjFun =
	case D#type.tablecinf of
	    [{objfun,_}|_R] ->
		", ObjFun";
	    _ ->
		""
	end,
    {Num,Buf} = gen_decode_length(SizeConstraint, Erules),
    emit([",",nl,
	  "'dec_",asn1ct_gen:list2name(Typename),
	  "_components'(",Num,", ",Buf,ObjFun,", []).",nl,nl]),
    gen_decode_sof_components(Erules, Typename, SeqOrSetOf, ComponentType).

is_aligned(per) -> true;
is_aligned(uper) -> false.

gen_decode_length(Constraint, Erule) ->
    emit(["%% Length with constraint ",{asis,Constraint},nl]),
    Imm = asn1ct_imm:per_dec_length(Constraint, true, is_aligned(Erule)),
    asn1ct_imm:dec_slim_cg(Imm, "Bytes").

gen_encode_sof_components(Erule,Typename,SeqOrSetOf,Cont) ->
    {ObjFun,ObjFun_Var} =
	case Cont#type.tablecinf of
	    [{objfun,_}|_R] ->
		{", ObjFun",", _"};
	    _ ->
		{"",""}
	end,
    emit({"'enc_",asn1ct_gen:list2name(Typename),"_components'([]",
	  ObjFun_Var,", Acc) -> lists:reverse(Acc);",nl,nl}),
    emit({"'enc_",asn1ct_gen:list2name(Typename),"_components'([H|T]",
	  ObjFun,", Acc) ->",nl}),
    emit({"'enc_",asn1ct_gen:list2name(Typename),"_components'(T"}), 
    emit({ObjFun,", ["}),
    %% the component encoder
    Constructed_Suffix = asn1ct_gen:constructed_suffix(SeqOrSetOf,
						       Cont#type.def),
    
    Conttype = asn1ct_gen:get_inner(Cont#type.def),
    Currmod = get(currmod),
    case asn1ct_gen:type(Conttype) of
	{primitive,bif} ->
	    asn1ct_gen_per:gen_encode_prim(Erule, Cont, "H");
	{constructed,bif} ->
	    NewTypename = [Constructed_Suffix|Typename],
	    emit({"'enc_",asn1ct_gen:list2name(NewTypename),"'(H",
		  ObjFun,")",nl,nl});
	#'Externaltypereference'{module=Currmod,type=Ename} ->
	    emit({"'enc_",Ename,"'(H)",nl,nl});
	#'Externaltypereference'{module=EMod,type=EType} ->
	    emit({"'",EMod,"':'enc_",EType,"'(H)",nl,nl});
	'ASN1_OPEN_TYPE' ->
	    asn1ct_gen_per:gen_encode_prim(Erule,
					   #type{def='ASN1_OPEN_TYPE'},
					   "H");
	_ ->
	    emit({"'enc_",Conttype,"'(H)",nl,nl})
    end,
    emit({" | Acc]).",nl}).

gen_decode_sof_components(Erule,Typename,SeqOrSetOf,Cont) ->
    {ObjFun,ObjFun_Var} =
	case Cont#type.tablecinf of
	    [{objfun,_}|_R] ->
		{", ObjFun",", _"};
	    _ ->
		{"",""}
	end,
    emit({"'dec_",asn1ct_gen:list2name(Typename),
	  "_components'(0, Bytes",ObjFun_Var,", Acc) ->",nl,
	  indent(3),"{lists:reverse(Acc), Bytes};",nl}),
    emit({"'dec_",asn1ct_gen:list2name(Typename),
	  "_components'(Num, Bytes",ObjFun,", Acc) ->",nl}),
    emit({indent(3),"{Term,Remain} = "}),
    Constructed_Suffix = asn1ct_gen:constructed_suffix(SeqOrSetOf,
						       Cont#type.def),
    Conttype = asn1ct_gen:get_inner(Cont#type.def),
    Ctgenmod = asn1ct_gen:ct_gen_module(Erule),
    case asn1ct_gen:type(Conttype) of
	{primitive,bif} ->
	    Ctgenmod:gen_dec_prim(Erule,Cont,"Bytes"),
	    emit({com,nl});
	{constructed,bif} ->
	    NewTypename = [Constructed_Suffix|Typename],
	    emit({"'dec_",asn1ct_gen:list2name(NewTypename),
		  "'(Bytes, telltype",ObjFun,"),",nl});
	#'Externaltypereference'{}=Etype ->
	    asn1ct_gen_per:gen_dec_external(Etype, "Bytes"),
	    emit([com,nl]);
	'ASN1_OPEN_TYPE' ->
	    Ctgenmod:gen_dec_prim(Erule,#type{def='ASN1_OPEN_TYPE'},
				  "Bytes"),
	    emit({com,nl});
	_ ->
	    emit({"'dec_",Conttype,"'(Bytes,telltype),",nl})
    end,
    emit({indent(3),"'dec_",asn1ct_gen:list2name(Typename),
	  "_components'(Num-1, Remain",ObjFun,", [Term|Acc]).",nl}).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% General and special help functions (not exported)

mkvlist([H|T]) ->
    emit(","),
    mkvlist2([H|T]);
mkvlist([]) ->
    true.
mkvlist2([H,T1|T]) ->
    emit({{var,H},","}),
    mkvlist2([T1|T]);
mkvlist2([H|T]) ->
    emit({{var,H}}),
    mkvlist2(T);
mkvlist2([]) ->
    true.


extensible_dec(CompList) when is_list(CompList) ->
    noext;
extensible_dec({RootList,ExtList}) ->
    {ext,length(RootList)+1,ext_length(ExtList)};
extensible_dec({Rl1,Ext,Rl2}) ->
     {ext,length(Rl1)+length(Rl2)+1,ext_length(Ext)}.

extensible_enc(CompList) when is_list(CompList) ->
    noext;
extensible_enc({RootList,ExtList}) ->
    {ext,length(RootList)+1,ext_length(ExtList)};
extensible_enc({Rl1,Ext,_Rl2}) ->
     {ext,length(Rl1)+1,ext_length(Ext)}.

ext_length(ExtList) -> ext_length(ExtList,normal,0).
ext_length([{'ExtensionAdditionGroup',_Num}|T],_,Acc)->
    ext_length(T,group,Acc);
ext_length(['ExtensionAdditionGroupEnd'|T],group,Acc) ->
    ext_length(T,normal,Acc+1);
ext_length([#'ComponentType'{}|T],State=group,Acc) ->
    ext_length(T,State,Acc);
ext_length([#'ComponentType'{}|T],State=normal,Acc) ->
    ext_length(T,State,Acc+1);
ext_length([],_,Acc) ->
    Acc.

extgroup_pos_and_length(CompList) when is_list(CompList) ->
    {extgrouppos,[]};
extgroup_pos_and_length({RootList,ExtList}) ->
    ActualPos = length(RootList) +1,
    %% position to get and deliver data in the record to the user
    VirtualPos = ActualPos,
    %% position to encode/decode the extaddgroup as an opentype sequence
    extgrouppos(ExtList,ActualPos,VirtualPos,[]);
extgroup_pos_and_length({RootList,ExtList,_Rl2}) ->
    extgroup_pos_and_length({RootList,ExtList}).

extgrouppos([{'ExtensionAdditionGroup',_Num}|T],ActualPos,VirtualPos,Acc) ->
    extgrouppos(T,ActualPos,VirtualPos,0,Acc);
extgrouppos([_|T],ActualPos,VirtualPos,Acc) ->
    extgrouppos(T,ActualPos+1,VirtualPos+1,Acc);
extgrouppos([],_,_,Acc) ->
    {extgrouppos,lists:reverse(Acc)}.

extgrouppos(['ExtensionAdditionGroupEnd'|T],ActualPos,VirtualPos,Len,Acc) ->
    extgrouppos(T,ActualPos+1,VirtualPos+Len,[{ActualPos,VirtualPos,Len}|Acc]);
extgrouppos([_|T],ActualPos,VirtualPos,Len,Acc) ->
    extgrouppos(T,ActualPos,VirtualPos,Len+1,Acc).


gen_dec_extension_value() ->
    Imm0 = {get_bits,1,[1]},
    E = fun(Imm, _) ->
		emit(["{Ext,",{next,bytes},"} = "]),
		BytesVar = asn1ct_gen:mk_var(asn1ct_name:curr(bytes)),
		asn1ct_imm:dec_code_gen(Imm, BytesVar),
		asn1ct_name:new(bytes)
	end,
    {imm,Imm0,E}.

gen_dec_optionals(Optionals) ->
    Imm0 = {get_bits,length(Optionals),[1]},
    E = fun(Imm, _) ->
		BytesVar = asn1ct_gen:mk_var(asn1ct_name:curr(bytes)),
		emit(["{Opt,",{next,bytes},"} = "]),
		asn1ct_imm:dec_code_gen(Imm, BytesVar),
		asn1ct_name:new(bytes)
    end,
    {imm,Imm0,E}.

gen_fixoptionals([{Pos,Def}|R]) ->
    asn1ct_name:new(fixopt),
    emit({{curr,fixopt}," = case element(",{asis,Pos},",",{curr,val},") of",nl,
	  "asn1_DEFAULT -> 0;",nl,
	  {asis,Def}," -> 0;",nl,
	  "_ -> 1",nl,
	  "end,",nl}),
    gen_fixoptionals(R);
gen_fixoptionals([Pos|R]) ->
    gen_fixoptionals([{Pos,asn1_NOVALUE}|R]);
gen_fixoptionals([]) ->
    ok.

    
param_map(Fun, [H]) ->
    [Fun(H)];
param_map(Fun, [H|T]) ->
    [Fun(H),","|param_map(Fun,T)].

    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Produce a list with positions (in the Value record) where
%% there are optional components, start with 2 because first element
%% is the record name

optionals({L1,Ext,L2}) ->
    Opt1 = optionals(L1,[],2),
    ExtComps = length([C||C = #'ComponentType'{}<-Ext]),
    Opt2 = optionals(L2,[],2+length(L1)+ExtComps),
    Opt1 ++ Opt2;
optionals({L,_Ext}) -> optionals(L,[],2); 
optionals(L) -> optionals(L,[],2).

optionals([{'EXTENSIONMARK',_,_}|Rest],Acc,Pos) ->
    optionals(Rest,Acc,Pos); % optionals in extension are currently not handled
optionals([#'ComponentType'{prop='OPTIONAL'}|Rest],Acc,Pos) ->
		 optionals(Rest,[Pos|Acc],Pos+1);
optionals([#'ComponentType'{prop={'DEFAULT',Val}}|Rest],Acc,Pos) ->
		 optionals(Rest,[{Pos,Val}|Acc],Pos+1);
optionals([#'ComponentType'{}|Rest],Acc,Pos) ->
		 optionals(Rest,Acc,Pos+1);
optionals([],Acc,_) ->
    lists:reverse(Acc).

%%%%%%%%%%%%%%%%%%%%%%
%% create_optionality_table(Cs=[#'ComponentType'{textual_order=undefined}|_]) ->
%%     {NewCs,_} = lists:mapfoldl(fun(C,Num) ->
%% 				       {C#'ComponentType'{textual_order=Num},
%% 					Num+1}
%% 			       end,
%% 			       1,Cs),
%%     create_optionality_table(NewCs);
create_optionality_table(Cs) ->
    IsOptional = fun('OPTIONAL') -> true;
		    ({'DEFAULT',_}) -> true;
		    (_) -> false
		 end,
    OptionalsElNum = [TO || #'ComponentType'{prop = O,textual_order=TO} <- Cs,
			   IsOptional(O)],
    {Table,_} = lists:mapfoldl(fun(X,Num) ->
				       {{Num,X},Num+1}
			       end,
			       1,lists:sort(OptionalsElNum)),
    Table.
get_optionality_pos(TextPos,OptTable) ->
    case lists:keysearch(TextPos,2,OptTable) of
	{value,{OptNum,_}} ->
	    OptNum;
	_ ->
	    no_num
    end.

to_encoding_order(Cs) when is_list(Cs) ->
    Cs;
to_encoding_order(Cs = {_Root,_Ext}) ->
    Cs;
to_encoding_order({R1,Ext,R2}) ->
    {R1++R2,Ext}.

add_textual_order(Cs) when is_list(Cs) ->
    {NewCs,_} = add_textual_order1(Cs,1),
    NewCs;
add_textual_order({Root,Ext}) ->
    {NewRoot,Num} = add_textual_order1(Root,1),
    {NewExt,_} = add_textual_order1(Ext,Num),
    {NewRoot,NewExt};
add_textual_order({R1,Ext,R2}) ->
    {NewR1,Num1} = add_textual_order1(R1,1),
    {NewExt,Num2} = add_textual_order1(Ext,Num1),
    {NewR2,_} = add_textual_order1(R2,Num2),
    {NewR1,NewExt,NewR2}.
%%add_textual_order1(Cs=[#'ComponentType'{textual_order=Int}|_],I)
%%  when is_integer(Int) ->
%%    {Cs,I};
add_textual_order1(Cs,NumIn) ->
    lists:mapfoldl(fun(C=#'ComponentType'{},Num) ->
			   {C#'ComponentType'{textual_order=Num},
			    Num+1};
		      (OtherMarker,Num) ->
			   {OtherMarker,Num}
		   end,
		   NumIn,Cs).

gen_enc_components_call(Erule,TopType,{Root,ExtList},MaybeComma,DynamicEnc,Ext) ->
    gen_enc_components_call(Erule,TopType,{Root,ExtList,[]},MaybeComma,DynamicEnc,Ext);
gen_enc_components_call(Erule,TopType,CL={Root,ExtList,Root2},MaybeComma,DynamicEnc,Ext) ->
    %% The type has extensionmarker
    Rpos = gen_enc_components_call1(Erule,TopType,Root++Root2,1,MaybeComma,DynamicEnc,noext),
    case Ext of
	{ext,_,ExtNum} when ExtNum > 0 ->
	    emit([nl,
		  ",Extensions",nl]);

	_ -> true
    end,
    %handle extensions
    {extgrouppos,ExtGroupPosLen}  = extgroup_pos_and_length(CL),
    NewExtList = wrap_extensionAdditionGroups(ExtList,ExtGroupPosLen),
    gen_enc_components_call1(Erule,TopType,NewExtList,Rpos,MaybeComma,DynamicEnc,Ext);
gen_enc_components_call(Erule,TopType, CompList, MaybeComma, DynamicEnc, Ext) ->
    %% The type has no extensionmarker
    gen_enc_components_call1(Erule,TopType,CompList,1,MaybeComma,DynamicEnc,Ext).

gen_enc_components_call1(Erule,TopType,
			 [C=#'ComponentType'{name=Cname,typespec=Type,prop=Prop}|Rest],
			 Tpos,
			 MaybeComma, DynamicEnc, Ext) ->

    put(component_type,{true,C}), 
    %% information necessary in asn1ct_gen_per_rt2ct:gen_encode_prim
    TermNo =
	case C#'ComponentType'.textual_order of
	    undefined ->
		Tpos;
	    CanonicalNum ->
		CanonicalNum
	end,
    emit(MaybeComma),
    case Prop of
	'OPTIONAL' ->
	    gen_enc_component_optional(Erule,TopType,Cname,Type,TermNo,DynamicEnc,Ext);
	{'DEFAULT',DefVal} ->
	    gen_enc_component_default(Erule,TopType,Cname,Type,TermNo,DynamicEnc,Ext,DefVal);
	_ ->
	    case Ext of
		{ext,ExtPos,_} when Tpos >= ExtPos ->
		    gen_enc_component_optional(Erule,TopType,Cname,Type,TermNo,DynamicEnc,Ext);
		_ ->
		    gen_enc_component_mandatory(Erule,TopType,Cname,Type,TermNo,DynamicEnc,Ext)
	    end
    end,

    erase(component_type),

    case Rest of
	[] ->
	    Tpos+1;
	_ ->
	    emit({com,nl}),
	    gen_enc_components_call1(Erule,TopType,Rest,Tpos+1,"",DynamicEnc,Ext)
    end;
gen_enc_components_call1(_Erule,_TopType,[],Pos,_,_,_) ->
	Pos.

gen_enc_component_default(Erule,TopType,Cname,Type,Pos,DynamicEnc,Ext,DefaultVal) ->
    Element = make_element(Pos+1,asn1ct_gen:mk_var(asn1ct_name:curr(val))),
    emit({"case ",Element," of",nl}),
%    emit({"asn1_DEFAULT -> [];",nl}),
    emit({"DFLT when DFLT == asn1_DEFAULT; DFLT == ",{asis,DefaultVal}," -> [];",nl}),

    asn1ct_name:new(tmpval),
    emit({{curr,tmpval}," ->",nl}),
    InnerType = asn1ct_gen:get_inner(Type#type.def),
    emit({nl,"%% attribute number ",Pos," with type ",
	      InnerType,nl}),
    NextElement = asn1ct_gen:mk_var(asn1ct_name:curr(tmpval)),
    gen_enc_line(Erule,TopType,Cname,Type,NextElement, Pos,DynamicEnc,Ext),
    emit({nl,"end"}).

gen_enc_component_optional(Erule,TopType,Cname,
			   Type=#type{def=#'SEQUENCE'{
					extaddgroup=Number,
					components=_ExtGroupCompList}},
			   Pos,DynamicEnc,Ext) when is_integer(Number) ->

    Element = make_element(Pos+1,asn1ct_gen:mk_var(asn1ct_name:curr(val))),
    emit({"case ",Element," of",nl}),

    emit({"asn1_NOVALUE -> [];",nl}),
    asn1ct_name:new(tmpval),
    emit({{curr,tmpval}," ->",nl}),
    InnerType = asn1ct_gen:get_inner(Type#type.def),
    emit({nl,"%% attribute number ",Pos," with type ",
	      InnerType,nl}),
    NextElement = asn1ct_gen:mk_var(asn1ct_name:curr(tmpval)),
    gen_enc_line(Erule,TopType,Cname,Type,NextElement, Pos,DynamicEnc,Ext),
    emit({nl,"end"});
gen_enc_component_optional(Erule,TopType,Cname,Type,Pos,DynamicEnc,Ext) ->
    Element = make_element(Pos+1,asn1ct_gen:mk_var(asn1ct_name:curr(val))),
    emit({"case ",Element," of",nl}),

    emit({"asn1_NOVALUE -> [];",nl}),
    asn1ct_name:new(tmpval),
    emit({{curr,tmpval}," ->",nl}),
    InnerType = asn1ct_gen:get_inner(Type#type.def),
    emit({nl,"%% attribute number ",Pos," with type ",
	      InnerType,nl}),
    NextElement = asn1ct_gen:mk_var(asn1ct_name:curr(tmpval)),
    gen_enc_line(Erule,TopType,Cname,Type,NextElement, Pos,DynamicEnc,Ext),
    emit({nl,"end"}).

gen_enc_component_mandatory(Erule,TopType,Cname,Type,Pos,DynamicEnc,Ext) ->
    InnerType = asn1ct_gen:get_inner(Type#type.def),
    emit({nl,"%% attribute number ",Pos," with type ",
	      InnerType,nl}),
    gen_enc_line(Erule,TopType,Cname,Type,[],Pos,DynamicEnc,Ext).

gen_enc_line(Erule,TopType, Cname, Type, [], Pos,DynamicEnc,Ext) ->
    Element = make_element(Pos+1,asn1ct_gen:mk_var(asn1ct_name:curr(val))),
    gen_enc_line(Erule,TopType,Cname,Type,Element, Pos,DynamicEnc,Ext);
gen_enc_line(Erule,TopType,Cname,Type,Element, _Pos,DynamicEnc,Ext) ->
    Atype = 
	case Type of
	    #type{def=#'ObjectClassFieldType'{type=InnerType}} ->
		InnerType;  
	    _  ->
		asn1ct_gen:get_inner(Type#type.def)
	end,

    case Ext of
	{ext,_Ep1,_} ->
	    asn1ct_func:need({Erule,encode_open_type,1}),
	    asn1ct_func:need({Erule,complete,1}),
	    emit(["encode_open_type(complete("]);
	_ -> true
    end,

    case Atype of
	{typefield,_} ->
	    case DynamicEnc of
		{_LeadingAttrName,Fun} ->
		    case (Type#type.def)#'ObjectClassFieldType'.fieldname of
			{Name,RestFieldNames} when is_atom(Name) ->
			    asn1ct_func:need({Erule,complete,1}),
			    asn1ct_func:need({Erule,encode_open_type,1}),
			    emit({"encode_open_type(complete(",nl}),
			    emit({"   ",Fun,"(",{asis,Name},", ",
				  Element,", ",{asis,RestFieldNames},")))"});
			Other ->
			    throw({asn1,{'internal error',Other}})
		    end
	    end;
	{objectfield,PrimFieldName1,PFNList} ->
	    case DynamicEnc of
		{_LeadingAttrName,Fun} ->
		    asn1ct_func:need({Erule,complete,1}),
		    asn1ct_func:need({Erule,encode_open_type,1}),
		    emit({"encode_open_type("
			  "complete(",nl}),
		    emit({"   ",Fun,"(",{asis,PrimFieldName1},
			  ", ",Element,", ",{asis,PFNList},")))"})
	    end;
	_ ->
	    CurrMod = get(currmod),
	    case asn1ct_gen:type(Atype) of
		#'Externaltypereference'{module=Mod,type=EType} when 
		      (CurrMod==Mod) ->
		    emit({"'enc_",EType,"'(",Element,")"});
		#'Externaltypereference'{module=Mod,type=EType} ->
		    emit({"'",Mod,"':'enc_",
			  EType,"'(",Element,")"});
		{primitive,bif} ->
		    asn1ct_gen_per:gen_encode_prim(Erule, Type, Element);
		'ASN1_OPEN_TYPE' ->
		    case Type#type.def of
			#'ObjectClassFieldType'{type=OpenType} ->
			    asn1ct_gen_per:gen_encode_prim(Erule,
							   #type{def=OpenType},
							   Element);
			_ ->
			    asn1ct_gen_per:gen_encode_prim(Erule, Type,
							   Element)
		    end;
		{constructed,bif} ->
		    NewTypename = [Cname|TopType],
		    case {Type#type.tablecinf,DynamicEnc} of
			{[{objfun,_}|_R],{_,EncFun}} ->
			    emit({"'enc_",
				  asn1ct_gen:list2name(NewTypename),
				  "'(",Element,", ",EncFun,")"});
			_ ->
			    emit({"'enc_",
				  asn1ct_gen:list2name(NewTypename),
				  "'(",Element,")"})
		    end
	    end
    end,
    case Ext of 
	{ext,_Ep2,_} ->
	    emit("))");
	_ -> true
    end.

gen_dec_components_call(Erule, TopType, {Root,ExtList},
			DecInfObj, Ext, NumberOfOptionals) ->
    gen_dec_components_call(Erule,TopType,{Root,ExtList,[]},
			    DecInfObj,Ext,NumberOfOptionals);
gen_dec_components_call(Erule,TopType,CL={Root1,ExtList,Root2},
			DecInfObj,Ext,NumberOfOptionals) ->
    %% The type has extensionmarker
    OptTable = create_optionality_table(Root1++Root2),
    Init = {ignore,fun(_) -> {[],[]} end},
    {EmitRoot,Tpos} =
	gen_dec_comp_calls(Root1++Root2, Erule, TopType, OptTable,
			   DecInfObj, noext, NumberOfOptionals,
			   1, []),
    EmitGetExt = gen_dec_get_extension(Erule),
    {extgrouppos,ExtGroupPosLen}  = extgroup_pos_and_length(CL),
    NewExtList = wrap_extensionAdditionGroups(ExtList, ExtGroupPosLen),
    {EmitExts,_} = gen_dec_comp_calls(NewExtList, Erule, TopType, OptTable,
				      DecInfObj, Ext, NumberOfOptionals,
				      Tpos, []),
    NumExtsToSkip = ext_length(ExtList),
    Finish =
	fun(St) ->
		emit([{next,bytes},"= "]),
		call(Erule, skipextensions,
		     [{curr,bytes},NumExtsToSkip+1,"Extensions"]),
		asn1ct_name:new(bytes),
		St
	end,
    [Init] ++ EmitRoot ++ [EmitGetExt|EmitExts] ++ [Finish];
gen_dec_components_call(Erule, TopType, CompList, DecInfObj,
			Ext, NumberOfOptionals) ->
    %% The type has no extensionmarker
    OptTable = create_optionality_table(CompList),
    Init = {ignore,fun(_) -> {[],[]} end},
    {Cs,_} = gen_dec_comp_calls(CompList, Erule, TopType, OptTable,
				DecInfObj, Ext, NumberOfOptionals,
				1, []),
    [Init|Cs].

gen_dec_get_extension(Erule) ->
    Imm0 = asn1ct_imm:per_dec_extension_map(is_aligned(Erule)),
    E = fun(Imm, St) ->
		emit([nl,"%% Extensions",
		      nl,
		      "{Extensions,",{next,bytes},"} = ",
		      "case Ext of",nl,
		      "0 -> {<<>>,",{curr,bytes},"};",nl,
		      "1 ->",nl]),
		BytesVar = asn1ct_gen:mk_var(asn1ct_name:curr(bytes)),
		{Dst,DstBuf} = asn1ct_imm:dec_slim_cg(Imm, BytesVar),
		emit([com,nl,
		      "{",Dst,",",DstBuf,"}",nl,
		      "end"]),
		asn1ct_name:new(bytes),
		St
	end,
    {imm,Imm0,E}.

gen_dec_comp_calls([C|Cs], Erule, TopType, OptTable, DecInfObj,
		   Ext, NumberOfOptionals, Tpos, Acc) ->
    L = gen_dec_comp_call(C, Erule, TopType, Tpos, OptTable, DecInfObj,
			  Ext, NumberOfOptionals),
    gen_dec_comp_calls(Cs, Erule, TopType, OptTable, DecInfObj,
		       Ext, NumberOfOptionals, Tpos+1, [L|Acc]);
gen_dec_comp_calls([], _, _, _, _, _, _, Tpos, Acc) ->
    {lists:append(lists:reverse(Acc)),Tpos}.

gen_dec_comp_call(Comp, Erule, TopType, Tpos, OptTable, DecInfObj,
		  Ext, NumberOfOptionals) ->
    #'ComponentType'{typespec=Type,prop=Prop,textual_order=TextPos} = Comp,
    Pos = case Ext of
	      noext -> Tpos;
	      {ext,Epos,_Enum} -> Tpos - Epos + 1
	  end,
    InnerType = 
	case Type#type.def of
	    #'ObjectClassFieldType'{type=InType} ->
		InType;
	    Def ->
		asn1ct_gen:get_inner(Def)
	end,

    DispType = case InnerType of
		   #'Externaltypereference'{type=T} -> T;
		   IT when is_tuple(IT) -> element(2,IT);
		   _ -> InnerType
	       end,
    Comment = fun(St) ->
		      emit([nl,"%% attribute number ",TextPos,
			    " with type ",DispType,nl]),
		      St
	      end,

    Preamble =
	case {InnerType,is_mandatory_predef_tab_c(Ext, Prop, DecInfObj)} of
	    {{typefield,_},true}  ->
		%% DecInfObj /= {"got objfun through args","ObjFun"} |
		%% (DecInfObj == {"got objfun through args","ObjFun"} &
		%% Ext == noext & Prop == mandatory)
		fun(St) ->
			asn1ct_name:new(term),
			asn1ct_name:new(tmpterm),
			emit(["{",{curr,tmpterm},", ",{next,bytes},"} = "]),
			St
		end;
	%%{objectfield,_,_} when Ext == noext, Prop == mandatory ->
	    {{objectfield,_,_},true} ->
		fun(St) ->
			asn1ct_name:new(term),
			asn1ct_name:new(tmpterm),
			emit(["{",{curr,tmpterm},", ",{next,bytes},"} = "]),
			St
		end;
	_ ->
	    case Type of
		#type{def=#'SEQUENCE'{
			extaddgroup=Number1,
			components=ExtGroupCompList1}} when is_integer(Number1)->
		    fun(St) ->
			    emit(["{{_,"]),
			    emit_extaddgroupTerms(term,ExtGroupCompList1),
			    emit(["}"]),
			    emit([",",{next,bytes},"} = "]),
			    St
		    end;
		_ ->
		    fun(St) ->
			    asn1ct_name:new(term),
			    emit(["{",{curr,term}]),
			    emit([",",{next,bytes},"} = "]),
			    St
		    end
	    end
	end,
    {Pre,Post} = comp_call_pre_post(Ext, Prop, Pos, Type, TextPos,
				    OptTable, NumberOfOptionals, Ext),
    Lines = gen_dec_seq_line_imm(Erule, TopType, Comp, Tpos, DecInfObj, Ext),
    AdvBuffer = {ignore,fun(St) ->
				asn1ct_name:new(bytes),
				St
			end},
    [{group,[{safe,Comment},{safe,Preamble}] ++ Pre ++
	  Lines ++ Post ++ [{safe,AdvBuffer}]}].

comp_call_pre_post(noext, mandatory, _, _, _, _, _, _) ->
    {[],[]};
comp_call_pre_post(noext, Prop, _, _, TextPos, OptTable, NumOptionals, Ext) ->
    %% OPTIONAL or DEFAULT
    OptPos = get_optionality_pos(TextPos, OptTable),
    Element = case NumOptionals - OptPos of
		  0 ->
		      "Opt band 1";
		  Shift ->
		      lists:concat(["(Opt bsr ",Shift,") band 1"])
	      end,
    {[fun(St) ->
	      emit(["case ",Element," of",nl,
		    "1 ->",nl]),
	      St
      end],
     [fun(St) ->
	      emit([";",nl,
		    "0 ->",nl,
		    "{"]),
	      gen_dec_component_no_val(Ext, Prop),
	      emit([",",{curr,bytes},"}",nl,
		    "end"]),
	      St
      end]};
comp_call_pre_post({ext,_,_}, Prop, Pos, Type, _, _, _, Ext) ->
    %% Extension
    {[fun(St) ->
	      emit(["case Extensions of",nl,
		    "  <<_:",Pos-1,",1:1,_/bitstring>> ->",nl]),
	      St
      end],
     [fun(St) ->
	      emit([";",nl,
		    "_  ->",nl,
		    "{"]),
	      case Type of
		  #type{def=#'SEQUENCE'{
			       extaddgroup=Number2,
			       components=ExtGroupCompList2}}
		    when is_integer(Number2)->
		      emit("{extAddGroup,"),
		      gen_dec_extaddGroup_no_val(Ext, ExtGroupCompList2),
		      emit("}");
		  _ ->
		      gen_dec_component_no_val(Ext, Prop)
	      end,
	      emit([",",{curr,bytes},"}",nl,
		    "end"]),
	      St
      end]}.

is_mandatory_predef_tab_c(noext, mandatory,
			  {"got objfun through args","ObjFun"}) ->
    true;
is_mandatory_predef_tab_c(_, _, {"got objfun through args","ObjFun"}) ->
    false;
is_mandatory_predef_tab_c(_,_,_) ->
    true.

gen_dec_extaddGroup_no_val(Ext,[#'ComponentType'{prop=Prop}])->
    gen_dec_component_no_val(Ext,Prop),
    ok;
gen_dec_extaddGroup_no_val(Ext,[#'ComponentType'{prop=Prop}|Rest])->
    gen_dec_component_no_val(Ext,Prop),
    emit({","}),
    gen_dec_extaddGroup_no_val(Ext,Rest);
gen_dec_extaddGroup_no_val(_, []) ->
    ok.

gen_dec_component_no_val(_,{'DEFAULT',DefVal}) ->
    emit([{asis,DefVal}]);
gen_dec_component_no_val(_,'OPTIONAL') ->
    emit({"asn1_NOVALUE"});
gen_dec_component_no_val({ext,_,_},mandatory) ->
    emit({"asn1_NOVALUE"}).
    

gen_dec_choice_line(Erule, TopType, Comp, Pre) ->
    Imm0 = gen_dec_line_imm(Erule, TopType, Comp, false, Pre),
    Init = {ignore,fun(_) -> {[],[]} end},
    Imm = [{group,[Init|Imm0]}],
    emit_gen_dec_imm(Imm).

gen_dec_seq_line_imm(Erule, TopType, Comp, Pos, DecInfObj, Ext) ->
    Pre = gen_dec_line_open_type(Erule, Ext, Pos),
    gen_dec_line_imm(Erule, TopType, Comp, DecInfObj, Pre).

gen_dec_line_imm(Erule, TopType, Comp, DecInfObj, Pre) ->
    #'ComponentType'{name=Cname,typespec=Type} = Comp,
    Atype = 
	case Type of
	    #type{def=#'ObjectClassFieldType'{type=InnerType}} ->
		InnerType;
	    _  ->
		asn1ct_gen:get_inner(Type#type.def)
	end,
    Decode = gen_dec_line_special(Erule, Atype, TopType, Comp, DecInfObj),
    Post =
	fun({SaveBytes,Finish}) ->
		{AccTerm,AccBytes} = Finish(),
		#'ComponentType'{name=Cname} = Comp,
		case DecInfObj of
		    {Cname,ObjSet} ->
			ObjSetRef =
			    case ObjSet of
				{deep,OSName,_,_} ->
				    OSName;
				_ -> ObjSet
			    end,
			{AccTerm++[{ObjSetRef,Cname,
				    asn1ct_gen:mk_var(asn1ct_name:curr(term))}],
			 AccBytes++SaveBytes};
		    _ ->
			{AccTerm,AccBytes++SaveBytes}
		end
	end,
    [Pre,Decode,{safe,Post}].

gen_dec_line_open_type(Erule, {ext,Ep,_}, Pos) when Pos >= Ep ->
    Imm = asn1ct_imm:per_dec_open_type(is_aligned(Erule)),
    {safe,fun(St) ->
		  emit(["begin",nl]),
		  BytesVar = asn1ct_gen:mk_var(asn1ct_name:curr(bytes)),
		  {Dst,DstBuf} = asn1ct_imm:dec_slim_cg(Imm, BytesVar),
		  emit([",",nl,"{TmpValx",Pos,",_} = "]),
		  {Dst,
		   fun() ->
			   emit([",",nl,
				 "{TmpValx",Pos,",",DstBuf,"}",nl,
				 "end"]),
			   St
		   end}
	  end};
gen_dec_line_open_type(_, _, _) ->
    {safe,fun(St) ->
		  {asn1ct_gen:mk_var(asn1ct_name:curr(bytes)),
		   fun() -> St end}
	  end}.

gen_dec_line_special(Erule, {typefield,_}, _TopType, Comp,
		     DecInfObj) ->
    #'ComponentType'{name=Cname,typespec=Type,prop=Prop} = Comp,
    fun({_BytesVar,PrevSt}) ->
	    case DecInfObj of
		false -> % This is in a choice with typefield components
		    {Name,RestFieldNames} =
			(Type#type.def)#'ObjectClassFieldType'.fieldname,

		    asn1ct_name:new(reason),
		    Imm = asn1ct_imm:per_dec_open_type(is_aligned(Erule)),
		    BytesVar = asn1ct_gen:mk_var(asn1ct_name:curr(bytes)),
		    {TmpTerm,TempBuf} = asn1ct_imm:dec_slim_cg(Imm, BytesVar),
		    emit([com,nl,
			  {next,bytes}," = ",TempBuf,com,nl,
			  indent(2),"case (catch ObjFun(",
			  {asis,Name},",",TmpTerm,",telltype,",
			  {asis,RestFieldNames},")) of", nl]),
		    emit([indent(4),"{'EXIT',",{curr,reason},"} ->",nl]),
		    emit([indent(6),"exit({'Type not ",
			  "compatible with table constraint', ",
			  {curr,reason},"});",nl]),
		    asn1ct_name:new(tmpterm),
		    emit([indent(4),"{",{curr,tmpterm},", _} ->",nl]),
		    emit([indent(6),"{",{asis,Cname},", {",{curr,tmpterm},", ",
			  {next,bytes},"}}",nl]),
		    emit([indent(2),"end"]),
		    {[],PrevSt};
		{"got objfun through args","ObjFun"} ->
		    %% this is when the generated code gots the
		    %% objfun though arguments on function
		    %% invocation.
		    if
			Prop =:= mandatory ->
			    ok;
			true ->
			    asn1ct_name:new(tmpterm),
			    asn1ct_name:new(tmpbytes),
			    emit([nl,"    {",{curr,tmpterm},", ",{curr,tmpbytes},"} ="])
		    end,
		    {Name,RestFieldNames} =
			(Type#type.def)#'ObjectClassFieldType'.fieldname,
		    Imm = asn1ct_imm:per_dec_open_type(is_aligned(Erule)),
		    BytesVar = asn1ct_gen:mk_var(asn1ct_name:curr(bytes)),
		    asn1ct_imm:dec_code_gen(Imm, BytesVar),
		    emit([com,nl]),
		    if
			Prop =:= mandatory ->
			    emit([{curr,term}," =",nl,"      "]);
			true ->
			    emit(["     {"])
		    end,
		    emit(["case (catch ObjFun(",{asis,Name},",",
			  {curr,tmpterm},",telltype,",
			  {asis,RestFieldNames},")) of", nl]),
		    emit(["    {'EXIT',",{curr,reason},"} ->",nl]),
		    emit([indent(6),"exit({'Type not ",
			  "compatible with table constraint', ",
			  {curr,reason},"});",nl]),
		    asn1ct_name:new(tmpterm),
		    emit([indent(4),"{",{curr,tmpterm},", _} ->",nl]),
		    emit([indent(6),{curr,tmpterm},nl]),
		    emit([indent(2),"end"]),
		    if
			Prop =:= mandatory ->
			    ok;
			true ->
			    emit([",",nl,{curr,tmpbytes},"}"])
		    end,
		    {[],PrevSt};
		_ ->
		    Imm = asn1ct_imm:per_dec_open_type(is_aligned(Erule)),
		    BytesVar = asn1ct_gen:mk_var(asn1ct_name:curr(bytes)),
		    asn1ct_imm:dec_code_gen(Imm, BytesVar),
		    RefedFieldName =
			(Type#type.def)#'ObjectClassFieldType'.fieldname,

		    {[{Cname,RefedFieldName,
		       asn1ct_gen:mk_var(asn1ct_name:curr(term)),
		       asn1ct_gen:mk_var(asn1ct_name:curr(tmpterm)),
		       Prop}],PrevSt}
	    end
    end;
gen_dec_line_special(Erule, {objectfield,PrimFieldName1,PFNList}, _TopType,
		     Comp, _DecInfObj) ->
    fun({_BytesVar,PrevSt}) ->
	    Imm = asn1ct_imm:per_dec_open_type(is_aligned(Erule)),
	    BytesVar = asn1ct_gen:mk_var(asn1ct_name:curr(bytes)),
	    asn1ct_imm:dec_code_gen(Imm, BytesVar),
	    #'ComponentType'{name=Cname,prop=Prop} = Comp,
	    SaveBytes = [{Cname,{PrimFieldName1,PFNList},
			  asn1ct_gen:mk_var(asn1ct_name:curr(term)),
			  asn1ct_gen:mk_var(asn1ct_name:curr(tmpterm)),
			  Prop}],
	    {SaveBytes,PrevSt}
    end;
gen_dec_line_special(Erule, Atype, TopType, Comp, DecInfObj) ->
    case gen_dec_line_other(Erule, Atype, TopType, Comp) of
	Fun when is_function(Fun, 1) ->
	    fun({BytesVar,PrevSt}) ->
		    Fun(BytesVar),
		    gen_dec_line_dec_inf(Comp, DecInfObj),
		    {[],PrevSt}
	    end;
	Imm0 ->
	    {imm,Imm0,
	     fun(Imm, {BytesVar,PrevSt}) ->
		     asn1ct_imm:dec_code_gen(Imm, BytesVar),
		     gen_dec_line_dec_inf(Comp, DecInfObj),
		     {[],PrevSt}
	     end}
    end.

gen_dec_line_dec_inf(Comp, DecInfObj) ->
    #'ComponentType'{name=Cname} = Comp,
    case DecInfObj of
	{Cname,{_,OSet,UniqueFName,ValIndex}} ->
	    Term = asn1ct_gen:mk_var(asn1ct_name:curr(term)),
	    ValueMatch = value_match(ValIndex,Term),
	    {ObjSetMod,ObjSetName} = OSet,
	    emit([",",nl,
		  "ObjFun = ",{asis,ObjSetMod},
		  ":'getdec_",ObjSetName,"'(",
		  {asis,UniqueFName},", ",ValueMatch,")"]);
	_ ->
	    ok
    end.

gen_dec_line_other(Erule, Atype, TopType, Comp) ->
    #'ComponentType'{name=Cname,typespec=Type} = Comp,
    case asn1ct_gen:type(Atype) of
	#'Externaltypereference'{}=Etype ->
	    fun(BytesVar) ->
		    asn1ct_gen_per:gen_dec_external(Etype, BytesVar)
	    end;
	{primitive,bif} ->
	    asn1ct_gen_per:gen_dec_imm(Erule, Type);
	'ASN1_OPEN_TYPE' ->
	    case Type#type.def of
		#'ObjectClassFieldType'{type=OpenType} ->
		    asn1ct_gen_per:gen_dec_imm(Erule, #type{def=OpenType});
		_ ->
		    asn1ct_gen_per:gen_dec_imm(Erule, Type)
	    end;
	{constructed,bif} ->
	    NewTypename = [Cname|TopType],
	    case Type#type.tablecinf of
		[{objfun,_}|_R] ->
		    fun(BytesVar) ->
			    emit({"'dec_",asn1ct_gen:list2name(NewTypename),
				  "'(",BytesVar,", telltype, ObjFun)"})
		    end;
		_ ->
		    fun(BytesVar) ->
			    emit({"'dec_",asn1ct_gen:list2name(NewTypename),
				  "'(",BytesVar,", telltype)"})
		    end
	    end
    end.

gen_enc_choice(Erule,TopType,CompList,Ext) ->
    gen_enc_choice_tag(Erule, CompList, [], Ext),
    emit({com,nl}),
    emit({"case element(1,Val) of",nl}),
    gen_enc_choice2(Erule,TopType, CompList, Ext),
    emit({nl,"end"}).

gen_enc_choice_tag(Erule, {C1,C2}, _, _) ->
    N1 = get_name_list(C1),
    N2 = get_name_list(C2),
    call(Erule,set_choice,
	 ["element(1, Val)",
	  {asis,{N1,N2}},
	  {asis,{length(N1),length(N2)}}]);
gen_enc_choice_tag(Erule, {C1,C2,C3}, _, _) ->
    N1 = get_name_list(C1),
    N2 = get_name_list(C2),
    N3 = get_name_list(C3),
    Root = N1 ++ N3,
    call(Erule,set_choice,
	 ["element(1, Val)",
	  {asis,{Root,N2}},
	  {asis,{length(Root),length(N2)}}]);
gen_enc_choice_tag(Erule, C, _, _) ->
    N = get_name_list(C),
    call(Erule,set_choice,
	 ["element(1, Val)",
	  {asis,N},{asis,length(N)}]).

get_name_list(L) ->
    get_name_list(L,[]).

get_name_list([#'ComponentType'{name=Name}|T], Acc) ->
    get_name_list(T,[Name|Acc]);
get_name_list([], Acc) ->
    lists:reverse(Acc).


gen_enc_choice2(Erule,TopType, {L1,L2}, Ext) ->
    gen_enc_choice2(Erule, TopType, L1 ++ L2, 0, [], Ext);
gen_enc_choice2(Erule, TopType, {L1,L2,L3}, Ext) ->
    gen_enc_choice2(Erule, TopType, L1 ++ L3 ++ L2, 0, [], Ext);
gen_enc_choice2(Erule,TopType, L, Ext) ->
    gen_enc_choice2(Erule,TopType, L, 0, [], Ext).

gen_enc_choice2(Erule, TopType, [H|T], Pos, Sep0, Ext) ->
    #'ComponentType'{name=Cname,typespec=Type} = H,
    EncObj =
	case asn1ct_gen:get_constraint(Type#type.constraint,
				       componentrelation) of
	    no -> 
		case Type#type.tablecinf of
		    [{objfun,_}|_] ->
			{"got objfun through args","ObjFun"};
		    _ ->
			false
		end;
	    _ ->
		{no_attr,"ObjFun"}
	end,
    emit([Sep0,{asis,Cname}," ->",nl]),
    DoExt = case Ext of
		{ext,ExtPos,_} when Pos + 1 < ExtPos -> noext;
		_ -> Ext
	    end,
    gen_enc_line(Erule, TopType, Cname, Type, "element(2, Val)",
		 Pos+1, EncObj, DoExt),
    Sep = [";",nl],
    gen_enc_choice2(Erule, TopType, T, Pos+1, Sep, Ext);
gen_enc_choice2(_, _, [], _, _, _)  -> ok.

%% Generate the code for CHOICE. If the CHOICE is extensible,
%% the structure of the generated code is as follows:
%%
%% case Bytes of
%%   <<0:1,Bytes1/bitstring>> ->
%%      Choice = <Decode INTEGER (0..LastRootChoice) from Bytes1>
%%      case Choice of
%%        0 -> <Decode>;
%%        :
%%        LastRootChoice -> <Decode>
%%      end;
%%   <<1:1,Bytes1/bitstring>> ->
%%      Choice = <Decode normally small number from Bytes1>
%%      TmpVal = <Decode open type>
%%      case Choice of
%%        0 -> <Decode TmpVal>;
%%        :
%%        LastExtension -> <Decode TmpVal>;
%%        _ -> <Return TmpVal since the type is unknown>
%%       end
%% end
%%
%% The return value from the generated function always looks like:
%%    {{ChoiceTag,Value},RemainingBuffer}
%% where ChoiceTag will be 'asn1_ExtAlt' for an unknown extension.
%%
%% If the CHOICE is not extensible, the top-level case is omitted
%% and only the code in the first case arm is generated.

gen_dec_choice(Erule, TopType, CompList, {ext,_,_}=Ext) ->
    {RootList,ExtList} = split_complist(CompList),
    emit(["case Bytes of",nl]),
    case RootList of
	[] ->
	    ok;
	[_|_] ->
	    emit(["<<0:1,Bytes1/bitstring>> ->",nl]),
	    asn1ct_name:new(bytes),
	    gen_dec_choice1(Erule, TopType, RootList, noext),
	    emit([";",nl,nl])
    end,
    emit(["<<1:1,Bytes1/bitstring>> ->",nl]),
    asn1ct_name:clear(),
    asn1ct_name:new(bytes),
    asn1ct_name:new(bytes),
    gen_dec_choice1(Erule, TopType, ExtList, Ext),
    emit([nl,"end"]);
gen_dec_choice(Erule, TopType, CompList, noext) ->
    gen_dec_choice1(Erule, TopType, CompList, noext).

split_complist({Root1,Ext,Root2}) ->
    {Root1++Root2,Ext};
split_complist({_,_}=CompList) ->
    CompList.

gen_dec_choice1(Erule, TopType, CompList, noext=Ext) ->
    emit_getchoice(Erule, CompList, Ext),
    emit(["case Choice of",nl]),
    Pre = {safe,fun(St) ->
			{asn1ct_gen:mk_var(asn1ct_name:curr(bytes)),
			 fun() -> St end}
		end},
    gen_dec_choice2(Erule, TopType, CompList, Pre),
    emit([nl,"end"]);
gen_dec_choice1(Erule, TopType, CompList, {ext,_,_}=Ext) ->
    emit_getchoice(Erule, CompList, Ext),
    Imm = asn1ct_imm:per_dec_open_type(is_aligned(Erule)),
    emit(["begin",nl]),
    BytesVar = asn1ct_gen:mk_var(asn1ct_name:curr(bytes)),
    {Dst,DstBuf} = asn1ct_imm:dec_slim_cg(Imm, BytesVar),
    emit([nl,
	  "end,",nl,
	  "case Choice of",nl]),
    Pre = {safe,fun(St) ->
			emit(["{TmpVal,_} = "]),
			{Dst,
			 fun() ->
				 emit([",",nl,
				       "{TmpVal,",DstBuf,"}"]),
				 St
			 end}
		end},
    gen_dec_choice2(Erule, TopType, CompList, Pre),
    case CompList of
	[] -> ok;
	[_|_] -> emit([";",nl])
    end,
    emit(["_ ->",nl,
	  "{{asn1_ExtAlt,",Dst,"},",DstBuf,"}",nl,
	  "end"]).

emit_getchoice(Erule, CompList, Ext) ->
    Al = is_aligned(Erule),
    Imm = case {Ext,CompList} of
	      {noext,[_]} ->
		  {value,0};
	      {noext,_} ->
		  asn1ct_imm:per_dec_constrained(0, length(CompList)-1, Al);
	      {{ext,_,_},_} ->
		  asn1ct_imm:per_dec_normally_small_number(Al)
	  end,
    emit(["{Choice,",{curr,bytes},"} = ",nl]),
    BytesVar = asn1ct_gen:mk_var(asn1ct_name:prev(bytes)),
    asn1ct_imm:dec_code_gen(Imm, BytesVar),
    emit([com,nl]).

gen_dec_choice2(Erule,TopType,L,Ext) ->
    gen_dec_choice2(Erule, TopType, L, 0, [], Ext).

gen_dec_choice2(Erule, TopType, [H0|T], Pos, Sep0, Pre) ->
    #'ComponentType'{name=Cname,typespec=Type} = H0,
    H = H0#'ComponentType'{prop=mandatory},
    emit([Sep0,Pos," ->",nl]),
    case Type#type.def of
	#'ObjectClassFieldType'{type={typefield,_}} ->
	    emit("{Cname,{Val,NewBytes}} = begin\n"),
	    gen_dec_choice_line(Erule, TopType, H, Pre),
	    emit([nl,
		  "end,",nl,
		  "{{Cname,Val},NewBytes}"]);
	_ ->
	    emit("{Val,NewBytes} = begin\n"),
	    gen_dec_choice_line(Erule, TopType, H, Pre),
	    emit([nl,
		  "end,",nl,
		  "{{",{asis,Cname},",Val},NewBytes}"])
    end,
    Sep = [";",nl],
    gen_dec_choice2(Erule, TopType, T, Pos+1, Sep, Pre);
gen_dec_choice2(_, _, [], _, _, _)  -> ok.

indent(N) ->
    lists:duplicate(N,32). % 32 = space

make_elements(I,Val,ExtCnames) ->
    make_elements(I,Val,ExtCnames,[]).

make_elements(I,Val,[_ExtCname],Acc)-> % the last one, no comma needed
    Element = make_element(I, Val),
    make_elements(I+1,Val,[],[Element|Acc]);
make_elements(I,Val,[_ExtCname|Rest],Acc)->
    Element = make_element(I, Val),
    make_elements(I+1,Val,Rest,[", ",Element|Acc]);
make_elements(_I,_,[],Acc) ->
    lists:reverse(Acc).

make_element(I, Val) ->
    io_lib:format("element(~w,~s)", [I,Val]).

emit_extaddgroupTerms(VarSeries,[_]) ->
    asn1ct_name:new(VarSeries),
    emit({curr,VarSeries}),
    ok;
emit_extaddgroupTerms(VarSeries,[_|Rest]) ->
    asn1ct_name:new(VarSeries),
    emit({{curr,VarSeries},","}),
    emit_extaddgroupTerms(VarSeries,Rest);
emit_extaddgroupTerms(_,[]) ->
    ok.

flat_complist({Rl1,El,Rl2}) -> Rl1 ++ El ++ Rl2;
flat_complist({Rl,El}) -> Rl ++ El;
flat_complist(CompList) -> CompList.

%%wrap_compList({Root1,Ext,Root2}) ->
%%    {Root1,wrap_extensionAdditionGroups(Ext),Root2};
%%wrap_compList({Root1,Ext}) ->
%%    {Root1,wrap_extensionAdditionGroups(Ext)};
%%wrap_compList(CompList) ->
%%    CompList.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  Will convert all componentTypes following 'ExtensionAdditionGroup'
%%  up to the matching 'ExtensionAdditionGroupEnd' into one componentType
%% of type SEQUENCE with the componentTypes as components
%%
wrap_extensionAdditionGroups(ExtCompList,ExtGroupPosLen) ->
    wrap_extensionAdditionGroups(ExtCompList,ExtGroupPosLen,[],0,0).

wrap_extensionAdditionGroups([{'ExtensionAdditionGroup',_Number}|Rest],
			     [{ActualPos,_,_}|ExtGroupPosLenRest],Acc,_ExtAddGroupDiff,ExtGroupNum) ->
    {ExtGroupCompList,['ExtensionAdditionGroupEnd'|Rest2]} =
	lists:splitwith(fun(#'ComponentType'{}) -> true;
			   (_) -> false
			end,
			Rest),
    wrap_extensionAdditionGroups(Rest2,ExtGroupPosLenRest,
				 [#'ComponentType'{
				     name=list_to_atom("ExtAddGroup"++
							integer_to_list(ExtGroupNum+1)), 
				     typespec=#type{def=#'SEQUENCE'{
						   extaddgroup=ExtGroupNum+1,
						   components=ExtGroupCompList}},
				     textual_order = ActualPos,
				     prop='OPTIONAL'}|Acc],length(ExtGroupCompList)-1,
				 ExtGroupNum+1);
wrap_extensionAdditionGroups([H=#'ComponentType'{textual_order=Tord}|T],
			     ExtAddGrpLenPos,Acc,ExtAddGroupDiff,ExtGroupNum) when is_integer(Tord) ->
    wrap_extensionAdditionGroups(T,ExtAddGrpLenPos,[H#'ComponentType'{
				      textual_order=Tord - ExtAddGroupDiff}|Acc],ExtAddGroupDiff,ExtGroupNum);
wrap_extensionAdditionGroups([H|T],ExtAddGrpLenPos,Acc,ExtAddGroupDiff,ExtGroupNum) ->
    wrap_extensionAdditionGroups(T,ExtAddGrpLenPos,[H|Acc],ExtAddGroupDiff,ExtGroupNum);
wrap_extensionAdditionGroups([],_,Acc,_,_) ->
    lists:reverse(Acc).

value_match(Index,Value) when is_atom(Value) ->
    value_match(Index,atom_to_list(Value));
value_match([],Value) ->
    Value;
value_match([{VI,_}|VIs],Value) ->
    value_match1(Value,VIs,lists:concat(["element(",VI,","]),1).
value_match1(Value,[],Acc,Depth) ->
    Acc ++ Value ++ lists:concat(lists:duplicate(Depth,")"));
value_match1(Value,[{VI,_}|VIs],Acc,Depth) ->
    value_match1(Value,VIs,Acc++lists:concat(["element(",VI,","]),Depth+1).

is_optimized(per) -> true;
is_optimized(uper) -> false.
