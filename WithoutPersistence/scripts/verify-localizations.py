#!/usr/bin/env python3
"""Audit new UI labels against the catalog and optionally a built app's real language resources."""
from pathlib import Path
import argparse,json,plistlib,re
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--shared-web',action='store_true',help='Also audit every label shared with Web')
parser.add_argument('--app',type=Path,help='Built Wishlist.app; verifies compiled Localizable.strings too')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]/'Wishlist'
catalog=json.loads((root/'Localizable.xcstrings').read_text())['strings']
languages=['zh-Hans','zh-Hant','en','es','ja','ko']
files=['Views/Settings/PrivacyPolicyView.swift','Views/Login/CloudAccountDeletionView.swift','Views/Login/ExpiredAccountArchiveView.swift','Views/Purchases/PurchasePlansView.swift','Models/StorePurchaseManager.swift','Views/Wallet/AgencyStatementExport.swift','Views/Wallet/AgencyStatementView.swift']
keys=set()
files.append('Views/Trips/TripPeriodSelector.swift')
files.append('Views/Settings/AppSettingsView.swift')
keys.add("请先在设置的“合作旅行社”中添加旅行社。")
for name in files:
 for text in re.findall(r'"([^"\n]*[\u4e00-\u9fff][^"\n]*)"',(root/name).read_text()):
  # Interpolated business strings, separators and comments are not catalog lookup keys.
  if '\\(' not in text and text not in ['—']:keys.add(text)
if args.shared_web:
 text=(root.parent/'web/localization.mjs').read_text()
 keys.update(json.loads(text[text.index('{'):text.index(';\nexport function')]))
compiled={code:plistlib.loads((args.app/f'{code}.lproj/Localizable.strings').read_bytes()) for code in languages} if args.app else {}
errors=[]
for key in sorted(keys):
 entry=catalog.get(key,{}).get('localizations',{})
 source=entry.get('zh-Hans',{}).get('stringUnit',{}).get('value',key)
 for code in languages:
  value=entry.get(code,{}).get('stringUnit',{}).get('value',source if code=='zh-Hans' else None)
  if not value:errors.append(f'{code}: missing {key}');continue
  if re.findall(r'%@|%ld',value)!=re.findall(r'%@|%ld',source):errors.append(f'{code}: placeholders {key}')
  # Xcode may omit a source-language entry when the key itself is the display value.
  fallback=key if code=='zh-Hans' and source==key else None
  if compiled and compiled[code].get(key,fallback)!=value:errors.append(f'{code}: compiled resource differs: {key}')
print(json.dumps({'languages':languages,'audited_keys':len(keys),'compiled_app':str(args.app) if args.app else None,'errors':errors},ensure_ascii=False,indent=2))
raise SystemExit(bool(errors))
