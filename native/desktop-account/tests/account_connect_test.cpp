#include "account_service.h"
#include <cassert>
using namespace kelpie::account;
using Json=nlohmann::json;
using kelpie::BookmarkStore;
int main() {
  int failures=0,refreshes=0,tickets=0;
  BookmarkStore bookmarks;
  AccountService service(bookmarks,[&](const std::string& path,const std::string&,const std::string& token,const std::string& body,const std::string&) -> AccountResponse {
    if(path=="/oauth/token") { ++refreshes; const auto grant=Json::parse(body);assert(grant["grant_type"]=="refresh_token" && !grant.contains("scope"));return {Json{{"access_token","rotated"},{"refresh_token","refresh-2"},{"expires_in",3600},{"token_type","Bearer"},{"scope",kAccountScopes}}.dump(),{}}; }
    if(path=="/oauth/me")return {R"({"sub":"owner","email":"owner@example.org"})",{}};
    if(path==kAccountBookmarks)return {R"({"value":[]})",{}};
    if(path=="/oauth/me/avatar")throw AccountFailure(404);
    if(path=="/oauth/revoke")return {"{}",{}};
    assert(path=="/oauth/kelpie/connect");++tickets;
    assert((Json::parse(body)==Json{{"resource","https://api.nessie.works/api/kelpie/connect"}}));
    if(failures) { const auto code=failures;failures=0;throw AccountFailure(code); }
    assert(token=="access" || token=="rotated");
    return {R"({"connection_ticket":"scoped","token_type":"Bearer","expires_in":120,"gateway_url":"wss://api.nessie.works/api/kelpie/connect"})",{}};
  });
  service.CompleteSignIn({"access",3600,"refresh-1","client"},0);
  assert(service.ConnectionOwner()==std::string(kAccountOrigin)+"/owner");
  failures=401;assert(service.ConnectionTicket()["connection_ticket"]=="scoped");assert(refreshes==1 && tickets==2);
  failures=403;bool refused=false;try { service.ConnectionTicket(); }catch(const AccountFailure& error) { refused=error.status==403; }
  assert(refused && service.State().signed_in && refreshes==1); // No widened refresh grant.
  service.SignOut();assert(service.ConnectionOwner().empty());
}
