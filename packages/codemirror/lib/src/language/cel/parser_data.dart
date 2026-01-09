/// Compiled parser tables for CEL (Common Expression Language).
///
/// This file was generated from the waku_cel_grammar Lezer grammar.
/// Do not edit directly.
library;

import 'package:lezer/lezer.dart';

/// Keyword specializers for identifiers.
const Map<String, int> _specIdentifier = {
  'true': 152,
  'false': 154,
  'null': 156,
  'in': 110,
};

/// Specializer specs for the CEL parser.
final List<SpecializerSpec> celParserSpecialized = [
  SpecializerSpec(term: 12, get: (value, stack) => _specIdentifier[value] ?? -1),
];

/// Parser states data (encoded).
const String celParserStates =
    r"/lOYQPOOOOQO'#Cj'#CjO!TQQO'#CgO#qQPO'#CiOYQPO'#CpO#vQPO'#CsO$QQPO'#CxOOQO'#C}'#C}OOQO'#DO'#DOOOQO'#Dy'#DyOOQO'#Cg'#CgO$[QQO'#CfOOQO'#Dl'#DlO%uQPO'#DVO&mQPO'#DXOOQO'#Ce'#CeO'bQQO'#CdO(uQQO'#CcO*hQQO'#CbO+XQPO'#CaO+vQPO'#C`O,bQPO'#DuOOQO'#Du'#DuQOQPOOO,yQPO'#CnOOQO,59T,59TO-QQPO,59TO-VQPO,59[OOQO'#Ct'#CtOYQPO'#CtO-[QPO'#DwOOQO,59_,59_O-dQPO,59_O-iQPO'#CyO-nQPO'#DxOOQO,59d,59dO-vQPO,59dO-{QSO'#DQO.TQPO'#DUOOQO'#D}'#D}OOQO'#Dk'#DkO.[QQO,59QOOQO-E7j-E7jOOQO,59q,59qOOQO,59s,59sOOQO'#EO'#EOOYQPO'#DmO/uQQO,59OOOQO'#EP'#EPOYQPO'#DnO1YQQO,58}OOQO'#EQ'#EQOYQPO'#DoO2dQQO,58|OYQPO'#DpO3TQPO,58{OYQPO'#DqO3rQPO,58zOYQPO,58yO4^QPO'#DvOOQO,59Y,59YO4fQPO,59YOOQO1G.o1G.oOOQO1G.v1G.vOOQO,59`,59`O4kQPO,5:cO4uQPO,5:cOOQO1G.y1G.yOYQPO,59eO4}QPO,5:dO5XQPO,5:dOOQO1G/O1G/OOOQO'#DR'#DRO5aQQO,59lO6}QSO,59lO7SQPO,59pOYQPO,59pOOQO-E7i-E7iOOQO,5:X,5:XOOQO-E7k-E7kOOQO,5:Y,5:YOOQO-E7l-E7lOOQO,5:Z,5:ZOOQO-E7m-E7mOOQO,5:[,5:[OOQO-E7n-E7nOOQO,5:],5:]OOQO-E7o-E7oO7XQPO1G.eO7^QPO,5:bO7eQPO,5:bOOQO1G.t1G.tOOQO,5:T,5:TO7mQPO1G/}OOQO-E7g-E7gOOQO1G/P1G/POOQO,5:U,5:UO7wQPO1G0OOOQO-E7h-E7hOOQO1G/Z1G/ZOOQO1G/W1G/WOOQO1G/[1G/[O8RQPO1G/[OYQPO7+$POOQO,5:S,5:SO8WQPO1G/|OOQO-E7f-E7fP#yQPO'#DiP#yQPO'#DjOOQO7+$v7+$vOOQO<<Gk<<GkPYQPO'#Dh";

/// Parser state data (encoded).
const String celParserStateData =
    r"8g~O!hOSPOS~O[QO_POaSOfTOkUOoXOpXOsXOz[O|^O!nVO!oVO!pWO~OahO_ZXfZXiZX|ZX}ZX!OZX!PZX!QZX!RZX!SZX!TZX!UZX!VZX!WZX!XZX!YZX!ZZX!fZX`ZXcZXeZXnZXjZX~O[jO~OeoOimO~PYOimOjsO~PYO_uOfvOiYX|YX}YX!OYX!PYX!QYX!RYX!SYX!TYX!UYX!VYX!WYX!XYX!YYX!ZYX!fYX`YXcYXeYXnYXjYX~O[QO_POaSOfTOkUOoXOpXOsXOz[O!nVO!oVO!pWO~O[QO_POaSOfTOkUOoXOpXOsXO!nVO!oVO!pWO~O}}O!O}O!P}OiWX|WX!QWX!RWX!SWX!TWX!UWX!VWX!WWX!XWX!YWX!ZWX!fWX`WXcWXeWXnWXjWX~O|!QO!Q!QOiVX!RVX!SVX!TVX!UVX!VVX!WVX!XVX!YVX!ZVX!fVX`VXcVXeVXnVXjVX~O!R!TO!S!TO!T!TO!U!TO!V!TO!W!TO!X!TO~OiUX!YUX!ZUX!fUX`UXcUXeUXnUXjUX~P*PO!Y!WOiTX!ZTX!fTX`TXcTXeTXnTXjTX~O!Z!YOiSX!fSX`SXcSXeSXnSXjSX~Oi![O!f!iX`!iXc!iXe!iXn!iXj!iX~O`!^O~PYOahO~O`!aO~Oc!cOe!kX~Oe!eO~On!fO~Oc!gOj!lX~Oj!iO~Oi!jOv!kO~Oi!jO~PYO_uOfvOiYa|Ya}Ya!OYa!PYa!QYa!RYa!SYa!TYa!UYa!VYa!WYa!XYa!YYa!ZYa!fYa`YacYaeYanYajYa~O}}O!O}O!P}OiWa|Wa!QWa!RWa!SWa!TWa!UWa!VWa!WWa!XWa!YWa!ZWa!fWa`WacWaeWanWajWa~O|!QO!Q!QOiVa!RVa!SVa!TVa!UVa!VVa!WVa!XVa!YVa!ZVa!fVa`VacVaeVanVajVa~OiUa!YUa!ZUa!fUa`UacUaeUanUajUa~P*PO!Y!WOiTa!ZTa!fTa`TacTaeTanTajTa~O!Z!YOiSa!fSa`SacSaeSanSajSa~Oc!{O`!jX~O`!}O~OimOe!ka~PYOc#POe!ka~OimOj!la~PYOc#TOj!la~OahO_taftaita|ta}ta!Ota!Pta!Qta!Rta!Sta!Tta!Uta!Vta!Wta!Xta!Yta!Zta!fta`tactaetantajta~Ov#WO~Oe#XO~On#ZO~O`!ja~PYOc#]O`!ja~OimOe!ki~PYOimOj!li~PYOe#aO~O`!ji~PYOP!Ospo[p~";

/// Parser goto table (encoded).
const String celParserGoto =
    r".q!uPPP!v#^#t$_$y%f&S&q'd P(R(pPPP)_P(RPP(R)hPPP(R)vPPP*O*OP*m*qP*m*m*wP*wPPPPPPPPPPPPPP+d+j+p+v+|,l,r,x-O-UPPP-[.W.Z.^(RPPP.a.e.i.myfOSTUhmv![!c!f!g!n!{#P#T#Z#]#_#`#cyeOSTUhmv![!c!f!g!n!{#P#T#Z#]#_#`#cxdOSTUhmv![!c!f!g!n!{#P#T#Z#]#_#`#cR!x!YzcOSTUhmv!Y![!c!f!g!n!{#P#T#Z#]#_#`#cR!v!W|bOSTUhmv!W!Y![!c!f!g!n!{#P#T#Z#]#_#`#cR!t!U!OaOSTUhmv!U!W!Y![!c!f!g!n!{#P#T#Z#]#_#`#cR!r!R!Q`OSTUhmv!R!U!W!Y![!c!f!g!n!{#P#T#Z#]#_#`#cR!p!O!S_OSTUhmv!O!R!U!W!Y![!c!f!g!n!{#P#T#Z#]#_#`#cQ{]R|^!XZOSTU]^hmv!O!R!U!W!Y![!c!f!g!n!{#P#T#Z#]#_#`#c!XYOSTU]^hmv!O!R!U!W!Y![!c!f!g!n!{#P#T#Z#]#_#`#c!XROSTU]^hmv!O!R!U!W!Y![!c!f!g!n!{#P#T#Z#]#_#`#cQiQQ!`jR#V!kQnTWqU!g#T#`V#O!c#P#_QrUV#S!g#T#`!XXOSTU]^hmv!O!R!U!W!Y![!c!f!g!n!{#P#T#Z#]#_#`#cTwZyQ!luR!nv!T_OSTUhmv!O!R!U!W!Y![!c!f!g!n!{#P#T#Z#]#_#`#cQ!|!]R#^!|Q!dnR#Q!dQ!hrR#U!hQyZR!oy!S]OSTUhmv!O!R!U!W!Y![!c!f!g!n!{#P#T#Z#]#_#`#cRz]Q!P`R!q!PQ!SaR!s!SQ!VbR!u!VQ!XcR!w!XQ!ZdR!y!ZQgOQkS`lTU!c!g#P#T#_#`Q!]hQ!bmQ!mvQ!z![Q#R!fQ#Y!nU#[!{#]#cR#b#ZR!_hRpTRtUTxZyT!O`!PT!Ra!ST!Ub!V";

/// Parser token data (encoded).
const String celParserTokenData =
    r"4r~RxXY#oYZ#o]^#opq#oqr$Qrs$_uv&Xvw&^wx&ixy(^yz(cz{(h{|(m|}(r}!O(w!O!P(|!P!Q)R!Q!R)r!R![+^![!],l!^!_,q!_!`-O!`!a-Z!a!b-h!c!d-m!d!e.Q!e!t-m!t!u2Y!u!}-m!}#O4R#P#Q4W#R#S-m#T#U-m#U#V.Q#V#f-m#f#g2Y#g#o-m#o#p4]#p#q4b#q#r4m~#tS!h~XY#oYZ#o]^#opq#oR$VPzP!_!`$YQ$_O!SQP$bXOY$_Z]$_^r$_rs$}s#O$_#O#P%S#P;'S$_;'S;=`&R<%lO$_P%SOpPP%VRO;'S$_;'S;=`%`;=`O$_P%cYOY$_Z]$_^r$_rs$}s#O$_#O#P%S#P;'S$_;'S;=`&R;=`<%l$_<%lO$_P&UP;=`<%l$_~&^O!P~~&aPvw&d~&iO!Y~P&lXOY&iZ]&i^w&iwx$}x#O&i#O#P'X#P;'S&i;'S;=`(W<%lO&iP'[RO;'S&i;'S;=`'e;=`O&iP'hYOY&iZ]&i^w&iwx$}x#O&i#O#P'X#P;'S&i;'S;=`(W;=`<%l&i<%lO&iP(ZP;=`<%l&i~(cOa~~(hO`~~(mO}~~(rO!Q~~(wOc~~(|O|~~)RO_~~)WP!O~!P!Q)Z~)`SP~OY)ZZ;'S)Z;'S;=`)l<%lO)Z~)oP;=`<%l)Z~)wVo~!O!P*^!Q![+^!g!h*r!w!x+u#X#Y*r#i#j+u#l#m+z~*aP!Q![*d~*iRo~!Q![*d!g!h*r#X#Y*r~*uR{|+O}!O+O!Q![+U~+RP!Q![+U~+ZPo~!Q![+U~+cUo~!O!P*^!Q![+^!g!h*r!w!x+u#X#Y*r#i#j+u~+zOo~~+}R!Q![,W!c!i,W#T#Z,W~,]To~!Q![,W!c!i,W!w!x+u#T#Z,W#i#j+u~,qOn~~,vP!T~!_!`,y~-OO!U~~-RP!_!`-U~-ZO!R~~-`P!V~!_!`-c~-hO!W~~-mOi~V-tSvS[R!Q![-m!c!}-m#R#S-m#T#o-mV.XUvS[Rrs.kwx0e!Q![-m!c!}-m#R#S-m#T#o-mP.nXOY.kZ].k^r.krs/Zs#O.k#O#P/`#P;'S.k;'S;=`0_<%lO.kP/`OsPP/cRO;'S.k;'S;=`/l;=`O.kP/oYOY.kZ].k^r.krs/Zs#O.k#O#P/`#P;'S.k;'S;=`0_;=`<%l.k<%lO.kP0bP;=`<%l.kP0hXOY0eZ]0e^w0ewx/Zx#O0e#O#P1T#P;'S0e;'S;=`2S<%lO0eP1WRO;'S0e;'S;=`1a;=`O0eP1dYOY0eZ]0e^w0ewx/Zx#O0e#O#P1T#P;'S0e;'S;=`2S;=`<%l0e<%lO0eP2VP;=`<%l0eV2aUvS[Rrs2swx3c!Q![-m!c!}-m#R#S-m#T#o-mP2vVOY2sZ]2s^r2srs$}s;'S2s;'S;=`3]<%lO2sP3`P;=`<%l2sP3fVOY3cZ]3c^w3cwx$}x;'S3c;'S;=`3{<%lO3cP4OP;=`<%l3c~4WOf~~4]Oe~~4bOk~~4eP#p#q4h~4mO!Z~~4rOj~";

/// Node names for the CEL parser.
const String celParserNodeNames =
    '⚠ LineComment Expression ConditionalExpr LogicalOrExpr LogicalAndExpr '
    'RelationExpr AdditionExpr MultiplicationExpr UnaryExpr MemberExpr '
    'PrimaryExpr Identifier GlobalCallExpr LeadingDot . ) ( ArgList , '
    'ParenExpr ] [ ListLiteral OptionalExpr ? } { MapLiteral MapEntry : '
    'Number String BooleanLiteral NullLiteral Bytes SelectExpr OptionalChain '
    'PropertyName CallExpr IndexExpr LogicalNotExpr Not NegationExpr Minus '
    'Star Slash Percent Plus Equals NotEquals LessThan LessThanEq GreaterThan '
    'GreaterThanEq in LogicalAnd LogicalOr';

/// Node props for the CEL parser (openedBy/closedBy).
const List<List<Object>> celParserNodeProps = [
  ['openedBy', 16, '(', 21, '[', 26, '{'],
  ['closedBy', 17, ')', 22, ']', 27, '}'],
];
