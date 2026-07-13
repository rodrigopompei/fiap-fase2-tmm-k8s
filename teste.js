import http from 'k6/http';

export const options = {
  vus: 50, // 50 usuários simultâneos
  duration: '1s',
};

export default function () {
  http.get('http://k8s-fiapfase2prod-56d43870fc-1665760791.us-east-2.elb.amazonaws.com/evaluation/evaluate?user_id=user-abc&flag_name=enable-new-dashboard');
}
